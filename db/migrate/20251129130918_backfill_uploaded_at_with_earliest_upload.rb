class BackfillUploadedAtWithEarliestUpload < ActiveRecord::Migration[8.1]
  # This was a data migration that has already run.
  # Made into a no-op to avoid issues with changing model APIs.
  def up
    # Previously backfilled uploaded_at with earliest upload timestamp
    # Run `bin/rails wc3stats:fix_uploaded_at` after deployment if needed
  end

  def down
  end
end
