class CreateGames < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.datetime :played_at
      t.integer :seconds

      t.timestamps
    end
  end
end
