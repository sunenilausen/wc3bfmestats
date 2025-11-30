class RecalculateMlScoresWithTeamHeal < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    say "Training prediction model with team heal contribution..."
    PredictionModelTrainer.new.train

    weights = PredictionWeight.current
    say "Model trained with accuracy: #{weights.accuracy}%, team_heal weight: #{weights.team_heal_contribution_weight}"

    say "Recalculating ML scores..."
    MlScoreRecalculator.new.call
    say "ML scores recalculated for #{Player.count} players"
  end

  def down
    # No-op: scores will be recalculated with current weights
  end
end
