class AddFlagToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :flagged, :boolean, default: false, null: false
    add_column :players, :flag_note, :text
    add_column :players, :flagged_at, :datetime

    add_index :players, :flagged
  end
end
