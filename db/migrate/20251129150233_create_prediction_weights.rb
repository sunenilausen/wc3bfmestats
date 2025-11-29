class CreatePredictionWeights < ActiveRecord::Migration[8.1]
  def change
    create_table :prediction_weights do |t|
      # Feature weights learned from historical data
      t.float :hero_kd_weight, default: 0.0
      t.float :hero_uptime_weight, default: 0.0
      t.float :base_uptime_weight, default: 0.0
      t.float :hero_kill_contribution_weight, default: 0.0
      t.float :unit_kill_contribution_weight, default: 0.0
      t.float :games_played_weight, default: 0.0
      t.float :elo_weight, default: 1.0  # Keep ELO as baseline

      # Bias term for the model
      t.float :bias, default: 0.0

      # Model metadata
      t.integer :games_trained_on, default: 0
      t.float :accuracy, default: 0.0
      t.datetime :last_trained_at

      t.timestamps
    end
  end
end
