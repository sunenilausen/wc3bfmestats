class AddReviewedToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :reviewed, :boolean, default: false, null: false
  end
end
