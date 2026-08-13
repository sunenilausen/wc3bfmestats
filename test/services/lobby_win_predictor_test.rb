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

  test "predicts roughly equal for identical teams with faction weight difference" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    # Create two players with identical stats (0 = average PERF on 0-centered scale)
    player1 = Player.create!(nickname: "Player1", custom_rating: 1500, ml_score: 0, custom_rating_games_played: 50)
    player2 = Player.create!(nickname: "Player2", custom_rating: 1500, ml_score: 0, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: player1)
    @lobby.lobby_players.create!(faction: evil_faction, player: player2)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert_not_nil prediction
    # Faction impact weights differ (Gondor: 1.05, Mordor: 1.08),
    # so identical CRs don't produce exactly 50/50
    assert_in_delta 50.0, prediction[:good_win_pct], 10.0
    assert_equal 100.0, prediction[:good_win_pct] + prediction[:evil_win_pct]
    # Mordor's higher weight means Evil is slightly favored
    assert prediction[:evil_win_pct] > prediction[:good_win_pct],
      "Mordor (1.08 weight) should be slightly favored over Gondor (1.05 weight)"
  end

  test "predicts higher win chance for stronger team" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    # Strong player vs weak player (experienced, so PERF doesn't affect CR)
    strong_player = Player.create!(nickname: "Strong", custom_rating: 1700, ml_score: 10, custom_rating_games_played: 50)
    weak_player = Player.create!(nickname: "Weak", custom_rating: 1300, ml_score: -10, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: strong_player)
    @lobby.lobby_players.create!(faction: evil_faction, player: weak_player)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert_not_nil prediction
    assert prediction[:good_win_pct] > 50, "Strong team should have >50% win chance"
    assert prediction[:evil_win_pct] < 50, "Weak team should have <50% win chance"
  end

  test "ML score adjusts effective CR for new players - penalty only" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    # New player with high ML score (good performer, +30 above average) - should NOT get bonus
    new_high_perf = Player.create!(nickname: "NewHighPerf", custom_rating: 1300, ml_score: 30, custom_rating_games_played: 0)
    # New player with low ML score (poor performer, -30 below average) - should get penalty
    new_low_perf = Player.create!(nickname: "NewLowPerf", custom_rating: 1300, ml_score: -30, custom_rating_games_played: 0)
    # Experienced player with average ML score
    exp_player = Player.create!(nickname: "ExpAvg", custom_rating: 1300, ml_score: 0, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: new_high_perf)
    @lobby.lobby_players.create!(faction: evil_faction, player: exp_player)

    predictor = LobbyWinPredictor.new(@lobby)

    # New player with high ML score should NOT have bonus (trust their CR)
    new_high_score = predictor.player_score(new_high_perf)
    assert_equal 1300, new_high_score[:effective_cr], "New high performer should use actual CR (no bonus)"
    assert_equal 0, new_high_score[:ml_adjustment], "No bonus for new players with ML >= 0"

    # New player with low ML score should get penalty
    # ML -30 at 0 games: (-30/50)*200 = -120 CR adjustment
    new_low_score = predictor.player_score(new_low_perf)
    assert_equal 1180, new_low_score[:effective_cr], "New low performer should have reduced effective CR"
    assert_equal(-120, new_low_score[:ml_adjustment], "ML adjustment should be -120 at 0 games with ML -30")

    # Experienced player should have no adjustment (30+ games)
    exp_score = predictor.player_score(exp_player)
    assert_equal 1300, exp_score[:effective_cr], "Experienced player should use actual CR"
    assert_equal 0, exp_score[:ml_adjustment], "No ML adjustment for experienced players"
  end

  test "ML penalty scales down as games increase - no bonus for new players" do
    good_faction = factions(:gondor)

    # Test penalty scaling (ML score < 0, i.e. below average)
    # ML -30 should give -120 penalty at 0 games
    player_0_games_low = Player.create!(nickname: "P0L", custom_rating: 1300, ml_score: -30, custom_rating_games_played: 0)
    player_15_games_low = Player.create!(nickname: "P15L", custom_rating: 1300, ml_score: -30, custom_rating_games_played: 15)
    player_30_games_low = Player.create!(nickname: "P30L", custom_rating: 1300, ml_score: -30, custom_rating_games_played: 30)

    # Test high ML score (> 0) - should NOT get bonus at any game count
    player_0_games_high = Player.create!(nickname: "P0H", custom_rating: 1300, ml_score: 30, custom_rating_games_played: 0)
    player_15_games_high = Player.create!(nickname: "P15H", custom_rating: 1300, ml_score: 30, custom_rating_games_played: 15)
    player_30_games_high = Player.create!(nickname: "P30H", custom_rating: 1300, ml_score: 30, custom_rating_games_played: 30)

    @lobby.lobby_players.create!(faction: good_faction, player: player_0_games_low)

    predictor = LobbyWinPredictor.new(@lobby)

    # Penalty (low ML score) scales down as games increase
    score_0_low = predictor.player_score(player_0_games_low)
    score_15_low = predictor.player_score(player_15_games_low)
    score_30_low = predictor.player_score(player_30_games_low)

    # At 0 games: full penalty (-120) for ML -30
    assert_equal(-120, score_0_low[:ml_adjustment])
    # At 15 games: half penalty (-60)
    assert_equal(-60, score_15_low[:ml_adjustment])
    # At 30 games: no penalty (0)
    assert_equal 0, score_30_low[:ml_adjustment]

    # High ML score (>= 0) - no bonus at any game count
    score_0_high = predictor.player_score(player_0_games_high)
    score_15_high = predictor.player_score(player_15_games_high)
    score_30_high = predictor.player_score(player_30_games_high)

    # All games: no bonus (0) - trust their CR
    assert_equal 0, score_0_high[:ml_adjustment], "No bonus for new players with ML >= 0"
    assert_equal 0, score_15_high[:ml_adjustment], "No bonus for new players with ML >= 0"
    assert_equal 0, score_30_high[:ml_adjustment], "No adjustment for experienced players"
  end

  test "handles new player placeholders" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    regular_player = Player.create!(nickname: "Regular", custom_rating: 1500, ml_score: 0, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: regular_player)
    @lobby.lobby_players.create!(faction: evil_faction, player: nil, is_new_player: true)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert_not_nil prediction
    # New player placeholder should use NewPlayerDefaults
    assert_equal NewPlayerDefaults.custom_rating, prediction[:evil_details][:avg_cr]
    assert_equal NewPlayerDefaults.ml_score, prediction[:evil_details][:avg_ml_score]
  end

  test "returns team details" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    # Experienced players (30+ games) so PERF doesn't affect effective CR
    player1 = Player.create!(nickname: "P1", custom_rating: 1600, ml_score: 10, custom_rating_games_played: 50)
    player2 = Player.create!(nickname: "P2", custom_rating: 1400, ml_score: -10, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: player1)
    @lobby.lobby_players.create!(faction: evil_faction, player: player2)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert_equal 1600, prediction[:good_details][:avg_cr]
    assert_equal 1600, prediction[:good_details][:avg_effective_cr], "Experienced players use actual CR"
    assert_equal 10, prediction[:good_details][:avg_ml_score]
    assert_equal 1400, prediction[:evil_details][:avg_cr]
    assert_equal 1400, prediction[:evil_details][:avg_effective_cr]
    assert_equal(-10, prediction[:evil_details][:avg_ml_score])
  end

  test "low ML score penalizes new players" do
    good_faction = factions(:gondor)
    evil_faction = factions(:mordor)

    # New player with low ML score (poor performer, -30 below average)
    new_low_perf = Player.create!(nickname: "NewLowPerf", custom_rating: 1300, ml_score: -30, custom_rating_games_played: 0)
    # Same CR player with average ML (experienced)
    avg_player = Player.create!(nickname: "Avg", custom_rating: 1300, ml_score: 0, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: good_faction, player: new_low_perf)
    @lobby.lobby_players.create!(faction: evil_faction, player: avg_player)

    predictor = LobbyWinPredictor.new(@lobby)
    prediction = predictor.predict

    # New player with low ML (-30) should have negative adjustment
    # ML -30 at 0 games: (-30/50)*200 = -120 CR adjustment
    low_score = predictor.player_score(new_low_perf)
    assert_equal 1180, low_score[:effective_cr], "Low ML new player should have reduced effective CR"
    assert_equal(-120, low_score[:ml_adjustment], "ML adjustment should be -120")

    # Evil should be favored since Good player has effective CR of 1180 vs 1300
    assert prediction[:evil_win_pct] > 50, "Team with actual 1300 CR should beat team with effective 1180 CR"
  end

  test "calibrated win chance is further from even than the raw balance of power" do
    strong = Player.create!(nickname: "Strong", custom_rating: 1700, ml_score: 0, custom_rating_games_played: 100)
    weak = Player.create!(nickname: "Weak", custom_rating: 1400, ml_score: 0, custom_rating_games_played: 100)

    @lobby.lobby_players.create!(faction: factions(:gondor), player: strong)
    @lobby.lobby_players.create!(faction: factions(:mordor), player: weak)

    prediction = LobbyWinPredictor.new(@lobby).predict

    assert prediction[:good_win_pct] > 50
    assert prediction[:true_good_win_pct] > prediction[:good_win_pct],
      "calibration should sharpen the favourite's chance"
    assert_in_delta 100.0, prediction[:true_good_win_pct] + prediction[:true_evil_win_pct], 0.2
  end

  test "margin of error is wider for inexperienced lobbies" do
    veteran_lobby = build_lobby(games_played: 200)
    rookie_lobby = build_lobby(games_played: 1)

    veteran = LobbyWinPredictor.new(veteran_lobby).predict
    rookie = LobbyWinPredictor.new(rookie_lobby).predict

    assert rookie[:cr_uncertainty] > veteran[:cr_uncertainty],
      "new players should make the rating estimate less certain"
    assert rookie[:true_margin_pct] > veteran[:true_margin_pct],
      "less certain ratings should widen the win chance band"
  end

  test "unknown new player slots carry the most uncertainty" do
    known_lobby = build_lobby(games_played: 1)
    unknown_lobby = Lobby.create!(session_token: "unknown-token")
    unknown_lobby.lobby_players.create!(faction: factions(:gondor), player: nil, is_new_player: true)
    unknown_lobby.lobby_players.create!(faction: factions(:mordor), player: nil, is_new_player: true)

    known = LobbyWinPredictor.new(known_lobby).predict
    unknown = LobbyWinPredictor.new(unknown_lobby).predict

    assert unknown[:cr_uncertainty] > known[:cr_uncertainty],
      "a completely unknown player should be less certain than a player with one game"
  end

  test "streaks widen the band without moving the win chance" do
    good = Player.create!(nickname: "GoodSide", custom_rating: 1500, ml_score: 0, custom_rating_games_played: 100)
    evil = Player.create!(nickname: "EvilSide", custom_rating: 1500, ml_score: 0, custom_rating_games_played: 100)
    @lobby.lobby_players.create!(faction: factions(:gondor), player: good)
    @lobby.lobby_players.create!(faction: factions(:mordor), player: evil)

    settled = LobbyWinPredictor.new(@lobby).predict

    good.update!(current_streak: -4)
    streaking = LobbyWinPredictor.new(@lobby.reload).predict

    assert_equal settled[:good_win_pct], streaking[:good_win_pct],
      "the raw balance of power must not move"
    assert_equal settled[:true_good_win_pct], streaking[:true_good_win_pct],
      "a streak says how well we know the rating, not which way the game goes"
    assert streaking[:true_margin_pct] > settled[:true_margin_pct],
      "a streak should widen the band"
    assert streaking[:cr_uncertainty] > settled[:cr_uncertainty]
  end

  test "a winning streak widens the band just as a losing one does" do
    winner = Player.create!(nickname: "Hot", custom_rating: 1500, ml_score: 0, custom_rating_games_played: 100, current_streak: 4)
    loser = Player.create!(nickname: "Cold", custom_rating: 1500, ml_score: 0, custom_rating_games_played: 100, current_streak: -4)

    assert_equal RatingUncertainty.streak_sigma(winner.current_streak),
                 RatingUncertainty.streak_sigma(loser.current_streak)
  end

  private

  def build_lobby(games_played:)
    lobby = Lobby.create!(session_token: "lobby-#{games_played}-#{SecureRandom.hex(4)}")
    [ factions(:gondor), factions(:mordor) ].each_with_index do |faction, i|
      player = Player.create!(
        nickname: "P#{games_played}-#{i}-#{SecureRandom.hex(3)}",
        custom_rating: 1500,
        ml_score: 0,
        custom_rating_games_played: games_played
      )
      lobby.lobby_players.create!(faction: faction, player: player)
    end
    lobby
  end
end
