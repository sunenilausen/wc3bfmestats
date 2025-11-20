class CreateWc3statsReplays < ActiveRecord::Migration[8.1]
  def change
    create_table :wc3stats_replays do |t|
      t.json :body
      t.integer :wc3stats_replay_id

      t.timestamps
    end
  end
end
