require "test_helper"

class MatchesHelperTest < ActionView::TestCase
  include MatchesHelper

  test "calibrated prediction sharpens the stored prediction" do
    match = matches(:one)
    match.update!(predicted_good_win_pct: 60.0)

    calibrated = calibrated_prediction(match)

    assert_not_nil calibrated
    assert calibrated[:good_pct] > 60.0, "expected calibration to sharpen the favourite"
    assert_in_delta 100.0, calibrated[:good_pct] + calibrated[:evil_pct], 0.2
  end

  test "no calibrated prediction without a stored one" do
    match = matches(:one)
    match.update!(predicted_good_win_pct: nil)

    assert_nil calibrated_prediction(match)
  end

  test "margin of error uses the game counts from the time of the match" do
    match = matches(:one)
    match.update!(predicted_good_win_pct: 55.0)

    match.appearances.each { |a| a.update!(games_played_before_match: 200, faction_games_before_match: 20) }
    veteran_uncertainty = historical_cr_uncertainty(match)

    match.appearances.each { |a| a.update!(games_played_before_match: 1, faction_games_before_match: 0) }
    rookie_uncertainty = historical_cr_uncertainty(match)

    assert rookie_uncertainty > veteran_uncertainty,
      "a lobby of new players should give a wider margin than a lobby of veterans"
  end

  test "streaks carried into the match widen the band, not the chance" do
    match = matches(:one)
    match.update!(predicted_good_win_pct: 50.0)
    match.appearances.each { |a| a.update!(streak_before_match: 0, games_played_before_match: 100, faction_games_before_match: 10) }
    settled = calibrated_prediction(match)

    match.appearances.each { |a| a.update!(streak_before_match: -4) }
    streaking = calibrated_prediction(match.reload)

    assert_equal settled[:good_pct], streaking[:good_pct], "the chance itself must not move"
    assert streaking[:margin_pct] > settled[:margin_pct], "the band should widen"
  end

  test "team win chance is stated from the player's own side" do
    match = matches(:one)
    match.update!(predicted_good_win_pct: 62.0)

    good = match.appearances.find { |a| a.faction.good? }
    evil = match.appearances.find { |a| !a.faction.good? }

    assert_equal 62.0, team_win_pct(good)
    assert_equal 38.0, team_win_pct(evil)
  end

  test "no team win chance without a stored prediction" do
    match = matches(:one)
    match.update!(predicted_good_win_pct: nil)

    assert_nil team_win_pct(match.appearances.first)
  end

  test "the balanced band matches the scope that defines it" do
    assert_equal :balanced, team_prediction_role(Match::BALANCED_PCT_RANGE.min)
    assert_equal :balanced, team_prediction_role(50)
    assert_equal :balanced, team_prediction_role(Match::BALANCED_PCT_RANGE.max)
    assert_equal :underdog, team_prediction_role(Match::BALANCED_PCT_RANGE.min - 0.1)
    assert_equal :favorite, team_prediction_role(Match::BALANCED_PCT_RANGE.max + 0.1)
  end

  test "match balance names the favoured side and how far from even it was" do
    match = matches(:one)

    match.update!(predicted_good_win_pct: 62.0)
    assert_equal({ side: "Good", pct: 62.0, band: :unbalanced }, match_balance(match))

    match.update!(predicted_good_win_pct: 38.0)
    assert_equal({ side: "Evil", pct: 62.0, band: :unbalanced }, match_balance(match))
  end

  test "balance bands mirror the lobby indicator" do
    assert_equal :balanced, balance_band(50)
    assert_equal :balanced, balance_band(Match::BALANCED_PCT_RANGE.max)
    assert_equal :possibly_unbalanced, balance_band(Match::BALANCED_PCT_RANGE.max + 0.1)
    assert_equal :possibly_unbalanced, balance_band(MatchesHelper::POSSIBLY_UNBALANCED_PCT)
    assert_equal :unbalanced, balance_band(MatchesHelper::POSSIBLY_UNBALANCED_PCT + 0.1)
  end

  test "no balance without a stored prediction" do
    match = matches(:one)
    match.update!(predicted_good_win_pct: nil)

    assert_nil match_balance(match)
  end

  test "host resolves to the player holding the battletag" do
    match = matches(:one)
    match.update!(host_battletag: players(:one).battletag)

    assert_equal players(:one), host_player(match)
    assert_equal({ match.id => players(:one) }, host_players_for([ match ]))
  end

  test "a host who played the match wins over a namesake who did not" do
    played_in_match = players(:one)
    namesake = Player.create!(nickname: "Namesake", battletag: "Shared#1")
    played_in_match.update!(alternative_battletags: [ "Shared#1" ])
    match = matches(:one)
    match.update!(host_battletag: "Shared#1")

    assert_equal namesake, Player.find_by_any_battletag("Shared#1"),
      "a plain lookup finds the namesake, which is what makes this worth testing"
    assert_equal played_in_match, host_player(match.reload),
      "the namesake never played, so the merged player is the host"
  end

  test "an unresolvable host battletag has no player" do
    match = matches(:one)
    match.update!(host_battletag: "Nobody#0000")

    assert_nil host_player(match)
    assert_empty host_players_for([ match ])
  end

  test "matches without a host battletag are skipped" do
    assert_empty host_players_for(Match.all)
  end

  test "hosts resolve for many matches at once" do
    matches(:one).update!(host_battletag: players(:one).battletag)
    matches(:two).update!(host_battletag: players(:two).battletag)

    hosts = host_players_for(Match.all)

    assert_equal players(:one), hosts[matches(:one).id]
    assert_equal players(:two), hosts[matches(:two).id]
  end

  test "rating adjustment comes from the snapshot frozen onto the appearance" do
    appearance = matches(:one).appearances.first
    appearance.update!(
      custom_rating: 1500,
      games_played_before_match: 100,
      faction_games_before_match: 0,
      ml_score_at_match: 0
    )

    breakdown = appearance_rating_adjustment(appearance)

    assert_equal 1500.0, breakdown.cr
    assert_equal(-LobbyWinPredictor::MAX_FACTION_FAMILIARITY_PENALTY, breakdown.familiarity.round,
      "a faction they had never played should cost the full penalty")
  end

  test "no rating adjustment for a match without the snapshot" do
    appearance = matches(:one).appearances.first
    appearance.update!(games_played_before_match: nil)

    assert_nil appearance_rating_adjustment(appearance)
  end

  test "no margin when the historical game counts were never backfilled" do
    match = matches(:one)
    match.update!(predicted_good_win_pct: 55.0)
    match.appearances.first.update!(games_played_before_match: nil)

    assert_nil historical_cr_uncertainty(match)
    assert_nil calibrated_prediction(match)[:margin_pct]
  end
end
