# Predicts match outcome for a lobby using players' ML scores
class LobbyScorePredictor
  attr_reader :lobby, :good_score, :evil_score, :player_scores

  def initialize(lobby)
    @lobby = lobby
    @player_scores = {}
  end

  def predict
    compute_team_scores

    return nil if @good_score.nil? || @evil_score.nil?

    # Convert score difference to win probability
    # ML scores are 0-100, centered at 50
    # Score difference determines win probability via sigmoid
    score_diff = @good_score - @evil_score
    good_win_probability = sigmoid(score_diff * 0.05)

    {
      good_win_pct: (good_win_probability * 100).round(1),
      evil_win_pct: ((1 - good_win_probability) * 100).round(1),
      good_score: @good_score.round(1),
      evil_score: @evil_score.round(1),
      player_scores: @player_scores
    }
  end

  private

  def compute_team_scores
    good_scores = []
    evil_scores = []

    @lobby.lobby_players.each do |lp|
      next unless lp.faction

      score = if lp.is_new_player? && lp.player_id.nil?
        NewPlayerDefaults.ml_score
      elsif lp.player
        lp.player.ml_score || NewPlayerDefaults.ml_score
      else
        next
      end

      @player_scores[lp.player_id || :new_player] = score

      if lp.faction.good?
        good_scores << score
      else
        evil_scores << score
      end
    end

    @good_score = good_scores.any? ? good_scores.sum / good_scores.size.to_f : nil
    @evil_score = evil_scores.any? ? evil_scores.sum / evil_scores.size.to_f : nil
  end

  def sigmoid(z)
    1.0 / (1.0 + Math.exp(-z.clamp(-500, 500)))
  end
end
