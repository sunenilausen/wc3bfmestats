class CreateLobbyObservers < ActiveRecord::Migration[8.1]
  def change
    create_table :lobby_observers do |t|
      t.references :lobby, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true

      t.timestamps
    end
  end
end
