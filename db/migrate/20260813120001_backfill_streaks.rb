class BackfillStreaks < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Walk match history once and record each player's streak going into every
  # match. Cheaper than a full rating recalculation, which would produce the
  # same values as a side effect.
  def up
    streaks = Hash.new(0)
    updates = []

    Match.where(ignored: false).includes(appearances: :faction).chronological.each do |match|
      match.appearances.each do |appearance|
        next unless appearance.player_id && appearance.faction
        updates << [ appearance.id, streaks[appearance.player_id] ]
      end

      # Draws neither extend nor break a streak
      next if match.is_draw?

      match.appearances.each do |appearance|
        next unless appearance.player_id && appearance.faction
        won = appearance.faction.good? == match.good_victory?
        streaks[appearance.player_id] = StreakAdjustment.next_streak(streaks[appearance.player_id], won)
      end
    end

    updates.each_slice(500) do |slice|
      slice.each { |id, streak| Appearance.where(id: id).update_all(streak_before_match: streak) }
    end

    streaks.each { |player_id, streak| Player.where(id: player_id).update_all(current_streak: streak) }

    say "Backfilled #{updates.size} appearances and #{streaks.size} players"
  end

  def down
    # No-op: don't remove data on rollback
  end
end
