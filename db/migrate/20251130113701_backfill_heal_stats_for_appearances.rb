class BackfillHealStatsForAppearances < ActiveRecord::Migration[8.1]
  # This was a data migration that has already run.
  # Made into a no-op to avoid issues with changing model APIs.
  def up
    # Previously backfilled heal stats from replay data
    # Run `bin/rails wc3stats:sync` after deployment if needed
  end

  def down
  end
end
