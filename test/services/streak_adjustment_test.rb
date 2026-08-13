require "test_helper"

class StreakAdjustmentTest < ActiveSupport::TestCase
  test "streaks extend and reset" do
    assert_equal 1, StreakAdjustment.next_streak(0, true)
    assert_equal 3, StreakAdjustment.next_streak(2, true)
    assert_equal(-1, StreakAdjustment.next_streak(2, false))
    assert_equal(-3, StreakAdjustment.next_streak(-2, false))
    assert_equal 1, StreakAdjustment.next_streak(-5, true)
  end
end
