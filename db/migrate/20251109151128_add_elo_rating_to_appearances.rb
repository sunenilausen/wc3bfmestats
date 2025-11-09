class AddEloRatingToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :elo_rating, :integer
    add_column :appearances, :elo_rating_change, :integer
  end
end
