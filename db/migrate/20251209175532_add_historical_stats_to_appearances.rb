class AddHistoricalStatsToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :overall_avg_rank, :decimal
    add_column :appearances, :faction_avg_rank, :decimal
    add_column :appearances, :perf_score, :decimal
    add_column :appearances, :faction_perf_score, :decimal
  end
end
