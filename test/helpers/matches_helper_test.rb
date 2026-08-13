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

  test "streaks carried into the match move the displayed chance" do
    match = matches(:one)
    match.update!(predicted_good_win_pct: 50.0)
    match.appearances.each { |a| a.update!(streak_before_match: 0) }

    assert_equal 0.0, calibrated_prediction(match)[:streak_shift_pct]

    # put the Good side on a losing streak - they were underrated at the time
    match.appearances.each do |a|
      a.update!(streak_before_match: a.faction.good? ? -4 : 0)
    end
    shifted = calibrated_prediction(match.reload)

    assert shifted[:streak_shift_pct] > 0
    assert shifted[:good_pct] > 50.0
  end

  test "no margin when the historical game counts were never backfilled" do
    match = matches(:one)
    match.update!(predicted_good_win_pct: 55.0)
    match.appearances.first.update!(games_played_before_match: nil)

    assert_nil historical_cr_uncertainty(match)
    assert_nil calibrated_prediction(match)[:margin_pct]
  end
end
