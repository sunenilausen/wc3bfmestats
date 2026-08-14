require "test_helper"

class CustomRatingRecalculatorTest < ActiveSupport::TestCase
  test "a debut appearance freezes the new-player PERF default" do
    match = matches(:one)
    match.update!(ignored: false, is_draw: false, good_victory: true)
    match.appearances.update_all(ml_score_at_match: nil, custom_rating: nil, custom_rating_change: nil)

    # a career PERF that must NOT leak into their first game's snapshot
    match.appearances.each { |a| a.player&.update!(ml_score: 25.0) }

    CustomRatingRecalculator.new.call

    debut = match.appearances.reload.detect { |a| a.games_played_before_match&.zero? && a.player }
    assert_not_nil debut, "expected the fixture match to contain a player's first game"
    assert_equal NewPlayerDefaults::ML_SCORE, debut.ml_score_at_match,
      "a player with no prior games should be frozen at the new-player default, not their eventual PERF"
  end

  test "an established player keeps their frozen PERF across recalculations" do
    match = matches(:one)
    match.update!(ignored: false, is_draw: false, good_victory: true)
    appearance = match.appearances.first
    appearance.update!(ml_score_at_match: 7.5, games_played_before_match: 50)

    CustomRatingRecalculator.new.call

    assert_equal 7.5, appearance.reload.ml_score_at_match,
      "ml_score_at_match is write-once - a later recalculation must not rewrite it"
  end
end
