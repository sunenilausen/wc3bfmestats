# Default values for new/unknown players in lobbies
class NewPlayerDefaults
  ELO = 1300
  GLICKO = 1200
  ML_SCORE = 35.0

  class << self
    def elo
      ELO
    end

    def glicko
      GLICKO
    end

    def ml_score
      ML_SCORE
    end

    # Returns all defaults as a hash
    def all
      {
        elo: elo,
        glicko: glicko,
        ml_score: ml_score
      }
    end
  end
end
