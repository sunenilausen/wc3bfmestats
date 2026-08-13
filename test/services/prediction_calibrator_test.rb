require "test_helper"

class PredictionCalibratorTest < ActiveSupport::TestCase
  class FakeMatch
    attr_reader :predicted_good_win_pct

    def initialize(predicted_good_win_pct, good_victory)
      @predicted_good_win_pct = predicted_good_win_pct
      @good_victory = good_victory
    end

    def good_victory? = @good_victory
  end

  test "leaves an even lobby alone" do
    assert_in_delta 50.0, PredictionCalibrator.calibrate(50.0), 0.1
  end

  test "pushes a favoured side further from even" do
    calibrated = PredictionCalibrator.calibrate(60.0)

    assert calibrated > 60.0, "expected 60% to calibrate upwards, got #{calibrated}"
    assert calibrated < 80.0, "expected a plausible stretch, got #{calibrated}"
  end

  test "stays symmetric around 50" do
    good = PredictionCalibrator.calibrate(57.0)
    evil = PredictionCalibrator.calibrate(43.0)

    assert_in_delta 100.0, good + evil, 0.2
  end

  test "never claims more certainty than the data supports" do
    assert_equal PredictionCalibrator::MAX_PCT, PredictionCalibrator.calibrate(99.9)
    assert_equal 100 - PredictionCalibrator::MAX_PCT, PredictionCalibrator.calibrate(0.1)
  end

  test "returns nil without a raw percentage" do
    assert_nil PredictionCalibrator.calibrate(nil)
  end

  test "band brackets the calibrated value and widens with uncertainty" do
    calibrated = PredictionCalibrator.calibrate(55.0)
    narrow_low, narrow_high = PredictionCalibrator.band(55.0, 40)
    wide_low, wide_high = PredictionCalibrator.band(55.0, 80)

    assert narrow_low < calibrated && calibrated < narrow_high
    assert wide_low < narrow_low, "more uncertainty should widen the band"
    assert wide_high > narrow_high, "more uncertainty should widen the band"
  end

  test "band is nil without uncertainty" do
    assert_nil PredictionCalibrator.band(55.0, 0)
    assert_nil PredictionCalibrator.band(nil, 40)
  end

  test "fit recovers a known stretch factor" do
    # Build outcomes that match sigmoid(logit(raw) * 2.0) exactly: for a raw
    # prediction of 60% the favoured side should win 69.2% of the time.
    raw = 60.0
    true_win_rate = PredictionCalibrator.send(:pct_from_logit, Math.log(0.6 / 0.4) * 2.0) / 100.0
    wins = (1000 * true_win_rate).round

    matches = Array.new(1000) { |i| FakeMatch.new(raw, i < wins) }

    assert_in_delta 2.0, PredictionCalibrator.fit(matches), 0.15
  end
end
