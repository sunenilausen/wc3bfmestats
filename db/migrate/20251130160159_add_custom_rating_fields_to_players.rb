class AddCustomRatingFieldsToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :custom_rating_games_played, :integer
    add_column :players, :custom_rating_reached_2000, :boolean
  end
end
