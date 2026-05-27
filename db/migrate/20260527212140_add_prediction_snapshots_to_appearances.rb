class AddPredictionSnapshotsToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :games_played_before_match, :integer
    add_column :appearances, :faction_games_before_match, :integer
    add_column :appearances, :ml_score_at_match, :decimal
  end
end
