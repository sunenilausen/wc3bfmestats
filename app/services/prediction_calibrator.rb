# Converts the raw "balance of power" percentage produced by LobbyWinPredictor
# into a statistically calibrated win probability.
#
# The raw percentage comes from sigmoid(cr_diff / 150), a scale chosen by hand.
# Measured against every stored match prediction it is systematically
# underconfident: lobbies the model calls 57% are won by the favoured team 66%
# of the time. Stretching the raw logit by a fitted factor K corrects this.
#
#   calibrated_logit = K * raw_logit
#
# K = 1.7 was fitted by maximum likelihood over all predicted matches, and
# validated walk-forward (fit on the past, score the next 200 matches): the
# out-of-sample Brier score improves from 0.2164 to 0.2113 across 1253 matches,
# with the fitted K staying between 1.60 and 1.80 in every window.
#
# This is a display-only transformation. The raw scale still defines "balanced"
# (Match.balanced, LobbyBalancer) and drives rating changes - restretching it
# there would silently redefine what a balanced lobby is.
#
# Refit with: bin/rails prediction:calibrate
class PredictionCalibrator
  # Fitted logit stretch factor
  K = 1.7

  # The sigmoid scale LobbyWinPredictor uses to turn a CR difference into a raw
  # percentage. Needed to translate a CR uncertainty into a probability band.
  RAW_DIVISOR = 150.0

  # Never claim more certainty than the data can support - there are fewer than
  # 100 matches above 75% raw confidence.
  MAX_PCT = 95.0

  class << self
    # Raw percentage (0-100) -> calibrated win percentage (0-100)
    def calibrate(raw_pct)
      return nil if raw_pct.nil?

      pct_from_logit(logit(raw_pct) * K)
    end

    # Win-probability band implied by an uncertainty of +/- cr_sigma in the
    # difference between the two teams' average CR.
    # Returns [low_pct, high_pct] around the calibrated percentage.
    def band(raw_pct, cr_sigma)
      return nil if raw_pct.nil? || cr_sigma.nil? || cr_sigma <= 0

      center = logit(raw_pct) * K
      spread = (cr_sigma / RAW_DIVISOR) * K

      [ pct_from_logit(center - spread), pct_from_logit(center + spread) ]
    end

    # Fit K by maximum likelihood over matches with a stored prediction.
    # Used by the prediction:calibrate rake task.
    def fit(matches)
      rows = matches.filter_map do |m|
        next if m.predicted_good_win_pct.nil?
        [ logit(m.predicted_good_win_pct), m.good_victory? ]
      end
      return nil if rows.empty?

      (0.5..4.0).step(0.05).max_by { |k| log_likelihood(rows, k) }
    end

    # Mean log-likelihood of the data under a given stretch factor
    def log_likelihood(rows, k)
      rows.sum do |raw_logit, good_won|
        p = (1.0 / (1 + Math.exp(-raw_logit * k))).clamp(1e-6, 1 - 1e-6)
        Math.log(good_won ? p : 1 - p)
      end
    end

    private

    def logit(pct)
      p = (pct / 100.0).clamp(0.001, 0.999)
      Math.log(p / (1 - p))
    end

    def pct_from_logit(z)
      pct = 100.0 / (1 + Math.exp(-z))
      pct.clamp(100 - MAX_PCT, MAX_PCT).round(1)
    end
  end
end
