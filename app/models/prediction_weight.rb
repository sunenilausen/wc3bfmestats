class PredictionWeight < ApplicationRecord
  # Retrain the model every N new matches
  RETRAIN_INTERVAL = 20

  # Returns the current (most recent) model weights
  def self.current
    order(created_at: :desc).first || create_default!
  end

  # Creates a default model with reasonable starting weights
  def self.create_default!
    create!(
      hero_kd_weight: 0.1,
      hero_kill_contribution_weight: 0.02,
      unit_kill_contribution_weight: 0.02,
      castle_raze_contribution_weight: 0.02,
      games_played_weight: 0.01,
      elo_weight: 1.0,
      enemy_elo_diff_weight: 0.0,
      bias: 0.0,
      games_trained_on: 0,
      accuracy: 0.0
    )
  end

  # Returns weights as a hash for easy use
  def weights_hash
    {
      hero_kd: hero_kd_weight,
      hero_kill_contribution: hero_kill_contribution_weight,
      unit_kill_contribution: unit_kill_contribution_weight,
      castle_raze_contribution: castle_raze_contribution_weight,
      games_played: games_played_weight,
      elo: elo_weight,
      enemy_elo_diff: enemy_elo_diff_weight,
      bias: bias
    }
  end

  # Check if the model should be retrained based on new matches
  def self.should_retrain?
    current_model = current
    total_matches = Match.where(ignored: false).count
    matches_since_training = total_matches - current_model.games_trained_on

    matches_since_training >= RETRAIN_INTERVAL
  end

  # Retrain if needed, returns the new model or nil if not needed
  def self.retrain_if_needed!
    return nil unless should_retrain?

    Rails.logger.info "PredictionWeight: Retraining model (#{RETRAIN_INTERVAL}+ new matches since last training)"
    PredictionModelTrainer.new.train
  end
end
