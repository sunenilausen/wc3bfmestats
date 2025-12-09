require "test_helper"

class LobbyWinPredictorTest < ActiveSupport::TestCase
  setup do
    @lobby = Lobby.create!(session_token: "test-token")
  end

  test "returns nil when no players assigned" do
    Faction.all.each do |faction|
      @lobby.lobby_players.create!(faction: faction, player: nil)
    end

    predictor = LobbyWinPredictor.new(@lobby)
    assert_nil predictor.predict
  end

  test "predicts 50/50 for identical teams" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    # Create two players with identical stats
    player1 = Player.create!(nickname: "Player1", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)
    player2 = Player.create!(nickname: "Player2", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: player1)
    @lobby.lobby_players.create!(faction: evil_faction, player: player2)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert_not_nil prediction
    assert_equal 50.0, prediction[:good_win_pct]
    assert_equal 50.0, prediction[:evil_win_pct]
  end

  test "predicts higher win chance for stronger team" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    # Strong player vs weak player
    strong_player = Player.create!(nickname: "Strong", custom_rating: 1700, ml_score: 60, custom_rating_games_played: 50)
    weak_player = Player.create!(nickname: "Weak", custom_rating: 1300, ml_score: 40, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: strong_player)
    @lobby.lobby_players.create!(faction: evil_faction, player: weak_player)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert_not_nil prediction
    assert prediction[:good_win_pct] > 50, "Strong team should have >50% win chance"
    assert prediction[:evil_win_pct] < 50, "Weak team should have <50% win chance"
  end

  test "uses adaptive CR/Rank weighting based on games played" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    # Brand new player (0 games) - 50% CR, 50% Rank
    brand_new_player = Player.create!(nickname: "BrandNew", custom_rating: 1300, custom_rating_games_played: 0)
    # Experienced player (100+ games) - 80% CR, 20% Rank
    exp_player = Player.create!(nickname: "ExpHighCR", custom_rating: 1600, custom_rating_games_played: 100)

    @lobby.lobby_players.create!(faction: good_faction, player: brand_new_player)
    @lobby.lobby_players.create!(faction: evil_faction, player: exp_player)

    predictor = LobbyWinPredictor.new(@lobby)

    # Check weighting for different experience levels
    brand_new_score = predictor.player_score(brand_new_player)
    exp_score = predictor.player_score(exp_player)

    # Brand new players (0 games): 50% CR, 50% Rank
    assert_equal 50, brand_new_score[:cr_weight], "Brand new player should have 50% CR weight"
    assert_equal 50, brand_new_score[:rank_weight], "Brand new player should have 50% Rank weight"

    # Experienced players (100+ games): 80% CR, 20% Rank
    assert_equal 80, exp_score[:cr_weight], "Experienced player should have 80% CR weight"
    assert_equal 20, exp_score[:rank_weight], "Experienced player should have 20% Rank weight"
  end

  test "handles new player placeholders" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    regular_player = Player.create!(nickname: "Regular", custom_rating: 1500, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: regular_player)
    @lobby.lobby_players.create!(faction: evil_faction, player: nil, is_new_player: true)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert_not_nil prediction
    # New player placeholder should use NewPlayerDefaults CR and default rank score of 25 (rank 4.0)
    assert_equal NewPlayerDefaults.custom_rating, prediction[:evil_details][:avg_cr]
    assert_equal 25.0, prediction[:evil_details][:avg_rank_score]
  end

  test "returns team details" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    player1 = Player.create!(nickname: "P1", custom_rating: 1600, custom_rating_games_played: 50)
    player2 = Player.create!(nickname: "P2", custom_rating: 1400, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: player1)
    @lobby.lobby_players.create!(faction: evil_faction, player: player2)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert_equal 1600, prediction[:good_details][:avg_cr]
    # Players with no appearance data get blended rank: 50% overall (4.0) + 50% faction (4.5) = 4.25
    # Rank score = (5.0 - 4.25) / 4.0 * 100 = 18.75, rounded to 18.8
    assert_equal 18.8, prediction[:good_details][:avg_rank_score]
    assert_equal 1400, prediction[:evil_details][:avg_cr]
    assert_equal 18.8, prediction[:evil_details][:avg_rank_score]
  end
end
