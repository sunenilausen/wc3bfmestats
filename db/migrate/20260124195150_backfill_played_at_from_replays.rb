class BackfillPlayedAtFromReplays < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    Match.joins(:wc3stats_replay).includes(:wc3stats_replay).find_each do |match|
      new_played_at = match.wc3stats_replay.played_at
      next unless new_played_at
      match.update_column(:played_at, new_played_at) unless match.played_at == new_played_at
    end
  end

  def down
    # No-op
  end
end
