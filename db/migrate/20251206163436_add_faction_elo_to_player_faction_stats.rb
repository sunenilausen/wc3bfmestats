class AddFactionEloToPlayerFactionStats < ActiveRecord::Migration[8.1]
  def change
    add_column :player_faction_stats, :faction_elo, :decimal
  end
end
