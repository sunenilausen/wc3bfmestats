# Win/loss streak bookkeeping.
#
# Streaks are recorded by CustomRatingRecalculator as it walks match history
# (players.current_streak, appearances.streak_before_match) and read back by the
# win chance meter, where a streak widens the uncertainty band.
#
# They deliberately do NOT move the predicted percentage. There is a measurable
# effect available - established players on a 4+ losing streak gain about 32 CR
# over their next 30 games, while those on a 4+ winning streak lose 4 - and
# feeding it into the meter did improve prediction slightly (log-likelihood
# +3.31, holdout Brier 0.2152 -> 0.2147). It was removed anyway: the displayed
# chance should say what the ratings say, and a streak is a reason to trust that
# number less rather than to redraw it.
#
# The uncertainty side lives in RatingUncertainty::STREAK_UNCERTAINTY_PER_STEP.
class StreakAdjustment
  class << self
    # The streak after a game, given the streak before it.
    # Draws neither extend nor break a streak, so they never reach here.
    def next_streak(streak, won)
      if won
        streak.to_i > 0 ? streak.to_i + 1 : 1
      else
        streak.to_i < 0 ? streak.to_i - 1 : -1
      end
    end
  end
end
