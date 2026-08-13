class AddStreakTracking < ActiveRecord::Migration[8.1]
  def change
    # Win/loss streak going into each match, for the historical win chance meter
    add_column :appearances, :streak_before_match, :integer

    # Current streak, for the lobby win chance meter
    add_column :players, :current_streak, :integer, default: 0, null: false
  end
end
