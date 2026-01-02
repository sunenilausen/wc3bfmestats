class AddIsEarlyLeaverToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :is_early_leaver, :boolean, default: false, null: false
  end
end
