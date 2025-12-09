class AddPredictedWinnerToMatches < ActiveRecord::Migration[8.1]
  def change
    # Predicted win percentage for Good team (0-100)
    add_column :matches, :predicted_good_win_pct, :decimal

    # Team average custom ratings at the time of prediction
    add_column :matches, :predicted_good_avg_rating, :decimal
    add_column :matches, :predicted_evil_avg_rating, :decimal
  end
end
