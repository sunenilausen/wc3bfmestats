class FixMapVersionsForBetaAndTestMaps < ActiveRecord::Migration[8.1]
  def up
    Match.joins(:wc3stats_replay).includes(:wc3stats_replay).find_each do |match|
      replay = match.wc3stats_replay
      new_version = replay.map_version

      # Update map version if needed
      if match.map_version != new_version
        match.update_column(:map_version, new_version)
      end

      # Ignore test maps
      if replay.test_map? && !match.ignored?
        match.update_column(:ignored, true)
      end
    end
  end

  def down
    # No rollback needed - map versions will be recalculated correctly
  end
end
