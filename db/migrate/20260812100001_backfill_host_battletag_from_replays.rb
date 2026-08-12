class BackfillHostBattletagFromReplays < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    Match.includes(:wc3stats_replay).where.not(wc3stats_replay_id: nil).find_each do |match|
      replay = match.wc3stats_replay
      next unless replay

      host = replay.host_battletag
      match.update_column(:host_battletag, host) if host.present?
    end
  end

  def down
    # No-op: don't remove data on rollback
  end
end
