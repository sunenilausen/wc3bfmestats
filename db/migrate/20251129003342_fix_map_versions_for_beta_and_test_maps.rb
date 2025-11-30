class FixMapVersionsForBetaAndTestMaps < ActiveRecord::Migration[8.1]
  # This was a data migration that has already run.
  # Made into a no-op to avoid issues with changing model APIs.
  def up
    # Previously fixed map versions and ignored test maps
    # Run `bin/rails wc3stats:sync` after deployment if needed
  end

  def down
  end
end
