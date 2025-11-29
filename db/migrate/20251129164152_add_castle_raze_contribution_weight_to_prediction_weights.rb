class AddCastleRazeContributionWeightToPredictionWeights < ActiveRecord::Migration[8.1]
  def change
    add_column :prediction_weights, :castle_raze_contribution_weight, :float, default: 0.02
  end
end
