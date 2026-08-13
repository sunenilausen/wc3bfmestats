require "test_helper"

class StreakAdjustmentTest < ActiveSupport::TestCase
  test "losing streaks read as underrated, winning streaks as overrated" do
    assert StreakAdjustment.cr_shift(-3) > 0, "a losing streak should raise the estimate"
    assert StreakAdjustment.cr_shift(3) < 0, "a winning streak should lower it"
    assert_equal 0.0, StreakAdjustment.cr_shift(0)
    assert_equal 0.0, StreakAdjustment.cr_shift(nil)
  end

  test "stops counting past the cap" do
    capped = StreakAdjustment.cr_shift(-StreakAdjustment::MAX_STEPS)

    assert_equal capped, StreakAdjustment.cr_shift(-20)
    assert_equal(-capped, StreakAdjustment.cr_shift(20))
  end

  test "team shift compares the two sides" do
    assert_equal 0.0, StreakAdjustment.team_cr_shift([ 2, 2 ], [ 2, 2 ])
    assert StreakAdjustment.team_cr_shift([ -3, -3 ], [ 1, 1 ]) > 0
    assert_equal 0.0, StreakAdjustment.team_cr_shift([], [ 1 ])
  end

  test "streaks extend and reset" do
    assert_equal 1, StreakAdjustment.next_streak(0, true)
    assert_equal 3, StreakAdjustment.next_streak(2, true)
    assert_equal(-1, StreakAdjustment.next_streak(2, false))
    assert_equal(-3, StreakAdjustment.next_streak(-2, false))
    assert_equal 1, StreakAdjustment.next_streak(-5, true)
  end
end
