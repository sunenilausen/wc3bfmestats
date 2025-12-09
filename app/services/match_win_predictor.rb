# Predicts match outcome based on players' ML scores at match time
class MatchWinPredictor
  attr_reader :match, :good_score, :evil_score

  def initialize(match)
    @match = match
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
      evil_score: @evil_score.round(1)
    }
  end

  # Predict and save to match
  def predict_and_save!
    prediction = predict
    return false unless prediction

    match.update_columns(
      predicted_good_win_pct: prediction[:good_win_pct],
      predicted_good_avg_rating: good_avg_rating,
      predicted_evil_avg_rating: evil_avg_rating,
      predicted_good_score: prediction[:good_score],
      predicted_evil_score: prediction[:evil_score]
    )
    true
  end

  private

  def compute_team_scores
    good_scores = []
    evil_scores = []

    match.appearances.each do |app|
      next unless app.faction

      player = app.player
      score = player&.ml_score || NewPlayerDefaults.ml_score

      if app.faction.good?
        good_scores << score
      else
        evil_scores << score
      end
    end

    @good_score = good_scores.any? ? good_scores.sum / good_scores.size.to_f : nil
    @evil_score = evil_scores.any? ? evil_scores.sum / evil_scores.size.to_f : nil
  end

  def good_avg_rating
    good_apps = match.appearances.select { |a| a.faction&.good? }
    return nil if good_apps.empty?
    good_apps.sum { |a| a.player&.custom_rating || 1300 } / good_apps.size.to_f
  end

  def evil_avg_rating
    evil_apps = match.appearances.select { |a| a.faction && !a.faction.good? }
    return nil if evil_apps.empty?
    evil_apps.sum { |a| a.player&.custom_rating || 1300 } / evil_apps.size.to_f
  end

  def sigmoid(z)
    1.0 / (1.0 + Math.exp(-z.clamp(-500, 500)))
  end
end
