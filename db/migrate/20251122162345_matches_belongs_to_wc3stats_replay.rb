class MatchesBelongsToWc3statsReplay < ActiveRecord::Migration[8.1]
  def change
    add_reference :matches, :wc3stats_replay, foreign_key: true, index: true
  end
end
