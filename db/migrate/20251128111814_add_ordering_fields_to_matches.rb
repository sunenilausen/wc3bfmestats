class AddOrderingFieldsToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :major_version, :integer
    add_column :matches, :build_version, :integer
    add_column :matches, :map_version, :string
    add_column :matches, :row_order, :integer

    add_index :matches, [:major_version, :build_version, :row_order, :map_version, :played_at, :wc3stats_replay_id],
              name: "index_matches_on_ordering"
  end
end
