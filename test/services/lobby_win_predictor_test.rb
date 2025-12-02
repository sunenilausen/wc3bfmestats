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

  test "uses more ML weight for new players" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    # New player with high ML but low CR
    new_player = Player.create!(nickname: "NewHighML", custom_rating: 1300, ml_score: 70, custom_rating_games_played: 5)
    # Experienced player with high CR but average ML
    exp_player = Player.create!(nickname: "ExpHighCR", custom_rating: 1600, ml_score: 50, custom_rating_games_played: 100)

    @lobby.lobby_players.create!(faction: good_faction, player: new_player)
    @lobby.lobby_players.create!(faction: evil_faction, player: exp_player)

    predictor = LobbyWinPredictor.new(@lobby)

    # Check that new player's score is calculated with higher ML weight
    new_score = predictor.player_score(new_player)
    exp_score = predictor.player_score(exp_player)

    assert_equal 40, new_score[:cr_weight], "New player should have 40% CR weight"
    assert_equal 60, new_score[:ml_weight], "New player should have 60% ML weight"
    assert_equal 70, exp_score[:cr_weight], "Experienced player should have 70% CR weight"
    assert_equal 30, exp_score[:ml_weight], "Experienced player should have 30% ML weight"
  end

  test "handles new player placeholders" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    regular_player = Player.create!(nickname: "Regular", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: regular_player)
    @lobby.lobby_players.create!(faction: evil_faction, player: nil, is_new_player: true)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert_not_nil prediction
    # New player placeholder should use NewPlayerDefaults values
    assert prediction[:evil_details][:avg_cr] == NewPlayerDefaults.custom_rating
    assert prediction[:evil_details][:avg_ml] == NewPlayerDefaults.ml_score
  end

  test "returns team details" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    player1 = Player.create!(nickname: "P1", custom_rating: 1600, ml_score: 55, custom_rating_games_played: 50)
    player2 = Player.create!(nickname: "P2", custom_rating: 1400, ml_score: 45, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: player1)
    @lobby.lobby_players.create!(faction: evil_faction, player: player2)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert_equal 1600, prediction[:good_details][:avg_cr]
    assert_equal 55.0, prediction[:good_details][:avg_ml]
    assert_equal 1400, prediction[:evil_details][:avg_cr]
    assert_equal 45.0, prediction[:evil_details][:avg_ml]
  end
end
