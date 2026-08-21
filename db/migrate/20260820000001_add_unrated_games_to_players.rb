class AddUnratedGamesToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :unrated_games, :integer, default: 0, null: false
  end
end
