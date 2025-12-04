class AddAlternativeBattletagsToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :alternative_battletags, :json, default: []
  end
end
