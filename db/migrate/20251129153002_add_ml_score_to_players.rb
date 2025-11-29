class AddMlScoreToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :ml_score, :float, default: 50.0
  end
end
