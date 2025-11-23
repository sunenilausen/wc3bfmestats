class CreateJoinTableLobbiesPlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :lobby_players do |t|
      t.references :lobby, null: false, foreign_key: true
      t.references :player, foreign_key: true
      t.references :faction, null: false, foreign_key: true
      t.timestamps
    end
  end
end
