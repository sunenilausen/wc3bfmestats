class AddCastlesRazedToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :castles_razed, :integer
  end
end
