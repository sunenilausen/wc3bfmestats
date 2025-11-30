class AddCustomRatingToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :custom_rating, :float
    add_column :players, :custom_rating_seed, :float
    add_column :players, :custom_rating_bonus_wins, :integer
  end
end
