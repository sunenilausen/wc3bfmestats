class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.string :battletag
      t.string :nickname
      t.string :battlenet_name
      t.float :elo_rating
      t.string :region
      t.integer :battlenet_number

      t.timestamps
    end
  end
end
