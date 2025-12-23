class BackfillIsDrawFromReplayData < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Backfill is_draw from replay data
    Match.includes(:wc3stats_replay).find_each do |match|
      next unless match.wc3stats_replay.present?

      is_draw = match.wc3stats_replay.is_draw?
      match.update_column(:is_draw, is_draw) if is_draw
    end
  end

  def down
    # Reset all is_draw to false
    Match.update_all(is_draw: false)
  end
end
