class AddMapVersionOrderToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :map_version_order, :integer
    add_index :matches, [ :map_version_order, :played_at ], name: "index_matches_on_version_ordering"
  end
end
