class CreateAppearances < ActiveRecord::Migration[8.1]
  def change
    create_table :appearances do |t|
      t.references :player, null: false, foreign_key: true
      t.references :faction, null: false, foreign_key: true
      t.references :match, null: false, foreign_key: true
      t.integer :unit_kills
      t.integer :hero_kills

      t.timestamps
    end
  end
end
