class AddStayLeaveStatsToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :stay_pct, :float, default: 100.0
    add_column :players, :leave_pct, :float, default: 0.0
    add_column :players, :games_stayed, :integer, default: 0
    add_column :players, :games_left, :integer, default: 0
  end
end
