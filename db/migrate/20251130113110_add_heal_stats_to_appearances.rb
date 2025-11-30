class AddHealStatsToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :self_heal, :integer
    add_column :appearances, :team_heal, :integer
    add_column :appearances, :total_heal, :integer
  end
end
