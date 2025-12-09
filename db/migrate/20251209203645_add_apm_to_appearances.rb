class AddApmToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :apm, :integer
  end
end
