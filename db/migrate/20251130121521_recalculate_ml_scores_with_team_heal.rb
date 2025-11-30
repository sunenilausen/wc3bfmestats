class RecalculateMlScoresWithTeamHeal < ActiveRecord::Migration[8.1]
  # This was a data migration that has already run.
  # Made into a no-op to avoid issues with changing service class APIs.
  def up
    # Previously called PredictionModelTrainer and MlScoreRecalculator
    # Run `bin/rails ml:train` after deployment if needed
  end

  def down
  end
end
