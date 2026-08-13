# How well we actually know a player's CR, and what that means for the
# uncertainty of a match prediction.
#
# The base numbers are measured: the standard deviation of how much a player's
# CR moves over their next 30 games, bucketed by how many games they had played
# at the time (bin/rails prediction:uncertainty).
#
# Used by LobbyWinPredictor for lobbies and MatchesHelper for finished matches,
# so both show a comparable margin of error.
class RatingUncertainty
  # Keys are upper bounds on games played
  CR_UNCERTAINTY_BY_GAMES = { 5 => 88.0, 10 => 81.0, 20 => 72.0, 30 => 63.0 }.freeze

  # Even a long-time player's rating drifts as their skill changes
  VETERAN_CR_UNCERTAINTY = 61.0

  # The measurement only covers players who stuck around long enough to have 30
  # more games, which truncates the spread for inexperienced players - the ones
  # who turned out to be far off their initial rating mostly quit. Inflate the
  # under-30-games buckets to account for that.
  SURVIVORSHIP_INFLATION = 1.25

  # A slot filled with "New Player" is someone we know nothing at all about
  UNKNOWN_PLAYER_CR_UNCERTAINTY = 140.0

  # Ratings go stale while a player is away. Keys are upper bounds in days.
  INACTIVITY_MULTIPLIERS = { 14 => 1.0, 60 => 1.05 }.freeze
  LONG_INACTIVITY_MULTIPLIER = 1.25

  # Extra uncertainty for a player on a faction they rarely play
  MAX_FAMILIARITY_UNCERTAINTY = 20.0

  # Extra uncertainty for a player on a run of wins or losses. A streak means
  # their rating is being pushed around faster than usual, so how well it
  # describes them right now is less clear.
  #
  # Unlike the numbers above this one is not measured: the spread of future CR
  # movement is flat across streak lengths (SD 60-62 in every bucket, n=715 to
  # 6016). It is a deliberate display choice, kept small for that reason.
  STREAK_UNCERTAINTY_PER_STEP = 8.0
  MAX_STREAK_STEPS = 4

  class << self
    # Uncertainty of a single player's CR.
    # unfamiliarity: 0 (their usual faction) to 1 (never played it)
    # streak: wins (positive) or losses (negative) in a row going in
    def player_sigma(games:, unfamiliarity: 0.0, inactivity_multiplier: 1.0, streak: 0)
      base_sigma(games) * inactivity_multiplier +
        unfamiliarity.clamp(0.0, 1.0) * MAX_FAMILIARITY_UNCERTAINTY +
        streak_sigma(streak)
    end

    # Either direction counts - the point is that the rating is moving, not
    # which way it is heading
    def streak_sigma(streak)
      return 0.0 if streak.nil?

      [ streak.abs, MAX_STREAK_STEPS ].min * STREAK_UNCERTAINTY_PER_STEP
    end

    def unknown_player_sigma
      UNKNOWN_PLAYER_CR_UNCERTAINTY
    end

    def base_sigma(games)
      _, sigma = CR_UNCERTAINTY_BY_GAMES.find { |max_games, _| games.to_i < max_games }
      sigma ? sigma * SURVIVORSHIP_INFLATION : VETERAN_CR_UNCERTAINTY
    end

    # nil means we have no record of them playing, which is at least as stale as
    # a long absence
    def inactivity_multiplier(last_played_at)
      return LONG_INACTIVITY_MULTIPLIER unless last_played_at

      days = (Time.current - last_played_at) / 1.day
      _, multiplier = INACTIVITY_MULTIPLIERS.find { |max_days, _| days < max_days }
      multiplier || LONG_INACTIVITY_MULTIPLIER
    end

    # Uncertainty of a team's average CR - individual errors are independent,
    # so variances add and the average divides by the team size
    def team_sigma(player_sigmas)
      return 0.0 if player_sigmas.empty?

      Math.sqrt(player_sigmas.sum { |sigma| sigma**2 }) / player_sigmas.size
    end

    # Uncertainty of the difference between the two team averages
    def combined_sigma(good_sigmas, evil_sigmas)
      Math.sqrt(team_sigma(good_sigmas)**2 + team_sigma(evil_sigmas)**2)
    end
  end
end
