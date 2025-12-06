class CreatePlayerFactionStats < ActiveRecord::Migration[8.1]
  def change
    create_table :player_faction_stats do |t|
      t.references :player, null: false, foreign_key: true
      t.references :faction, null: false, foreign_key: true
      t.integer :games_played, default: 0, null: false
      t.integer :wins, default: 0, null: false
      t.float :performance_score, default: 0.0, null: false
      t.integer :rank

      t.timestamps
    end

    add_index :player_faction_stats, [ :player_id, :faction_id ], unique: true
    add_index :player_faction_stats, [ :faction_id, :rank ]
    add_index :player_faction_stats, [ :faction_id, :performance_score ]
  end
end
