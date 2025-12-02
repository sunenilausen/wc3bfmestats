class AddContributionPercentagesToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :hero_kill_pct, :float
    add_column :appearances, :unit_kill_pct, :float
    add_column :appearances, :castle_raze_pct, :float
    add_column :appearances, :heal_pct, :float
    add_column :appearances, :team_heal_pct, :float
  end
end
