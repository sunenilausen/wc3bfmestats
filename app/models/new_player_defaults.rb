# Default values for new/unknown players in lobbies
class NewPlayerDefaults
  # PERF score uses 0-centered scale (0 = average, negative = below average)
  # -15 is a conservative estimate for unknown players
  ML_SCORE = -15.0
  CUSTOM_RATING = 1300

  class << self
    def ml_score
      ML_SCORE
    end

    def custom_rating
      CUSTOM_RATING
    end

    # Returns all defaults as a hash
    def all
      {
        ml_score: ml_score,
        custom_rating: custom_rating
      }
    end
  end
end
