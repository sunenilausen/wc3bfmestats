class AddContributionFieldsToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :contribution_rank, :integer
    add_column :appearances, :contribution_bonus, :integer
    add_column :appearances, :is_mvp, :boolean, default: false
    add_column :appearances, :performance_score, :float
  end
end
