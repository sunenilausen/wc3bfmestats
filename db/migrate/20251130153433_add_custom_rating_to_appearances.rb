class AddCustomRatingToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :custom_rating, :integer
    add_column :appearances, :custom_rating_change, :integer
  end
end
