class AddPredictedTeamScoresToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :predicted_good_score, :decimal
    add_column :matches, :predicted_evil_score, :decimal
  end
end
