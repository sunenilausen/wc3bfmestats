class AddPlayedAtToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :played_at, :datetime

    # Update the ordering index with played_at as the primary ordering field
    remove_index :matches, name: "index_matches_on_ordering", if_exists: true
    add_index :matches,
      [ :played_at, :major_version, :build_version, :row_order, :map_version, :uploaded_at, :wc3stats_replay_id ],
      name: "index_matches_on_ordering"

    # Backfill played_at and uploaded_at from replay data
    reversible do |dir|
      dir.up do
        Match.joins(:wc3stats_replay).includes(:wc3stats_replay).find_each do |match|
          replay = match.wc3stats_replay
          changes = {}

          # played_at: from filename or fallback to earliest upload
          played_at = replay.played_at
          changes[:played_at] = played_at if played_at

          # uploaded_at: always the earliest upload timestamp
          uploaded_at = replay.earliest_upload_at
          changes[:uploaded_at] = uploaded_at if uploaded_at && match.uploaded_at != uploaded_at

          match.update_columns(changes) if changes.any?
        end
      end
    end
  end
end
