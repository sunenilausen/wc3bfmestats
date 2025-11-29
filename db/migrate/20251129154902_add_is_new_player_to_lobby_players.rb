class AddIsNewPlayerToLobbyPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :lobby_players, :is_new_player, :boolean, default: false
  end
end
