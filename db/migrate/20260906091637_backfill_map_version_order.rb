class BackfillMapVersionOrder < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Versioned matches first, so the handful without a readable map version
    # have something to date themselves against.
    Match.where.not(map_version: nil).find_each do |match|
      rank = MapVersionOrder.rank(match.map_version)
      match.update_column(:map_version_order, rank) if rank
    end

    Match.where(map_version_order: nil).find_each do |match|
      rank = MapVersionOrder.rank_for(match.map_version, played_at: match.played_at)
      match.update_column(:map_version_order, rank) if rank
    end
  end

  def down
    # No-op: don't remove data on rollback
  end
end
