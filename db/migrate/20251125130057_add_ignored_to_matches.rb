class AddIgnoredToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :ignored, :boolean, default: false, null: false
  end
end
