class RenamePlayedAtToUploadedAtInMatches < ActiveRecord::Migration[8.1]
  def change
    rename_column :matches, :played_at, :uploaded_at
  end
end
