class FixDebutMlScoreSnapshots < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # ml_score_at_match is deliberately write-once, so these rows will never be
  # corrected by a recalculation on their own.
  #
  # Appearances that were a player's very first game were frozen with whatever
  # ml_score that player happened to carry when the snapshot was taken - which,
  # for history backfilled during a later recalculation, is their eventual
  # career PERF. That leaked hindsight into the stored prediction and disagreed
  # with the lobby, which rates an unknown player at the new-player default.
  #
  # A debut player has no performance history, so the correct value is knowable:
  # it is that same default.
  def up
    fixed = Appearance.where(games_played_before_match: 0)
                      .where.not(ml_score_at_match: NewPlayerDefaults::ML_SCORE)
                      .update_all(ml_score_at_match: NewPlayerDefaults::ML_SCORE)

    say "Reset #{fixed} debut appearances to the new-player PERF default (#{NewPlayerDefaults::ML_SCORE})"
    say "Run `bin/rails wc3stats:recalculate` to rebuild the stored predictions from these values"
  end

  def down
    # No-op: the previous values were hindsight-contaminated, nothing to restore
  end
end
