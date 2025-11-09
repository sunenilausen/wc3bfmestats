class CreateFactions < ActiveRecord::Migration[8.1]
  def change
    create_table :factions do |t|
      t.string :name
      t.boolean :good
      t.string :color

      t.timestamps
    end
  end
end
