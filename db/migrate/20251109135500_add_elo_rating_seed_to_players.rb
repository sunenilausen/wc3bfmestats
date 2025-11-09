class AddEloRatingSeedToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :elo_rating_seed, :float
  end
end
