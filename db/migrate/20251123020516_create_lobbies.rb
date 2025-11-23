class CreateLobbies < ActiveRecord::Migration[8.1]
  def change
    create_table :lobbies do |t|
      t.timestamps
    end
  end
end
