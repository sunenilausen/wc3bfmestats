class AddEnemyEloDiffWeightToPredictionWeights < ActiveRecord::Migration[8.1]
  def change
    add_column :prediction_weights, :enemy_elo_diff_weight, :float, default: 0.0
  end
end
