class AddTeamHealContributionWeightToPredictionWeights < ActiveRecord::Migration[8.1]
  def change
    add_column :prediction_weights, :team_heal_contribution_weight, :float, default: 0.0
  end
end
