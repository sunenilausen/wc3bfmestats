class AddHasEarlyLeaverToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :has_early_leaver, :boolean, default: false, null: false
  end
end
