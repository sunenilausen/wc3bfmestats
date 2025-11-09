class RenameGameToMatch < ActiveRecord::Migration[8.1]
  def change
    rename_table :games, :matches
  end
end
