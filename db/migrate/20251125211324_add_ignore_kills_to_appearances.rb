class AddIgnoreKillsToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :ignore_unit_kills, :boolean, default: false, null: false
    add_column :appearances, :ignore_hero_kills, :boolean, default: false, null: false
  end
end
