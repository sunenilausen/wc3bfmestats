class BackfillUploadedAtWithEarliestUpload < ActiveRecord::Migration[8.1]
  def up
    # Update all matches to use the earliest upload timestamp from their replay
    Match.joins(:wc3stats_replay).find_each do |match|
      replay = match.wc3stats_replay
      earliest_upload = replay.played_at # This now returns the earliest upload timestamp

      if earliest_upload && match.uploaded_at != earliest_upload
        match.update_column(:uploaded_at, earliest_upload)
      end
    end
  end

  def down
    # No-op: we can't restore the old values
  end
end
