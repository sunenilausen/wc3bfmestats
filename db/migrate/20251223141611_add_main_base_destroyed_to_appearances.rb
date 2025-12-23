class AddMainBaseDestroyedToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :main_base_destroyed, :integer
  end
end
