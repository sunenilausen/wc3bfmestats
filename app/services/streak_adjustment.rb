# Players on a losing streak are underrated, players on a winning streak are
# overrated - their CR has been pushed away from where it is heading.
#
# Measured on established players (30+ games), by the streak going into a game,
# looking at how much their CR moves over the next 30 games:
#
#   losing 4+   +31.8    winning 2   +7.3
#   losing 3    +17.1    winning 3   +2.0
#   losing 2    +16.7    winning 4+  -4.0
#   no streak   +11.0
#
# The spread around those means is flat (SD 60-62 in every bucket), so a streak
# says which way the rating is displaced, not that it is less reliable. It
# belongs in the middle of the win chance meter, never in its error band.
#
# CR_PER_STEP was fitted by maximum likelihood against match outcomes: adding
# this term improves log-likelihood by 3.31 (a parameter needs ~1.9 to earn its
# place) and holds up on a 70/30 holdout (Brier 0.2152 -> 0.2147).
#
# Display only. Feeding it back into ratings would fight the rating system's own
# dynamics, and it deliberately does not touch the raw "Balance of Power" number
# that defines a balanced lobby or drives the LobbyBalancer.
class StreakAdjustment
  CR_PER_STEP = 6.0

  # Streaks stop carrying extra information past this length
  MAX_STEPS = 4

  class << self
    # CR the player's rating is displaced by, given their streak going in.
    # Negative streak (losses) gives a positive shift - they are underrated.
    def cr_shift(streak)
      return 0.0 if streak.nil?

      -streak.clamp(-MAX_STEPS, MAX_STEPS) * CR_PER_STEP
    end

    # Shift in the difference between the two teams' average CR
    def team_cr_shift(good_streaks, evil_streaks)
      return 0.0 if good_streaks.empty? || evil_streaks.empty?

      average_shift(good_streaks) - average_shift(evil_streaks)
    end

    # The streak after a game, given the streak before it
    def next_streak(streak, won)
      if won
        streak.to_i > 0 ? streak.to_i + 1 : 1
      else
        streak.to_i < 0 ? streak.to_i - 1 : -1
      end
    end

    private

    def average_shift(streaks)
      streaks.sum { |streak| cr_shift(streak) } / streaks.size
    end
  end
end
