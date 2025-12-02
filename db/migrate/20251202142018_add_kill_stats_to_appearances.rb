class AddKillStatsToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :top_hero_kills, :boolean, default: false
    add_column :appearances, :top_unit_kills, :boolean, default: false
    add_column :appearances, :heroes_lost, :integer
    add_column :appearances, :heroes_total, :integer
    add_column :appearances, :bases_lost, :integer
    add_column :appearances, :bases_total, :integer
  end
end
