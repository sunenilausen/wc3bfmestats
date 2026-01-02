class BackfillHistoricalStatsToAppearances < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Process matches in chronological order
    # For each appearance, calculate what the player's stats were BEFORE this match

    # Track cumulative stats per player
    player_ranks = Hash.new { |h, k| h[k] = [] }  # player_id => [ranks]
    player_faction_ranks = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } }  # player_id => { faction_id => [ranks] }

    # We need to also track PERF scores, but those require more complex calculation
    # For now, we'll use current ml_score and faction_score as approximation
    # since recalculating historical PERF scores would require replaying all matches

    total = Match.where(ignored: false).count
    processed = 0

    Match.includes(appearances: [ :player, :faction ])
         .where(ignored: false)
         .chronological
         .find_each do |match|
      match.appearances.each do |appearance|
        next unless appearance.player_id && appearance.faction_id

        player_id = appearance.player_id
        faction_id = appearance.faction_id

        # Calculate averages from matches BEFORE this one
        prev_ranks = player_ranks[player_id]
        prev_faction_ranks = player_faction_ranks[player_id][faction_id]

        overall_avg = prev_ranks.any? ? (prev_ranks.sum / prev_ranks.size.to_f).round(2) : nil
        faction_avg = prev_faction_ranks.any? ? (prev_faction_ranks.sum / prev_faction_ranks.size.to_f).round(2) : nil

        # Get current PERF scores (approximation - ideally would be historical)
        player = appearance.player
        perf = player&.ml_score
        faction_perf = PlayerFactionStat.find_by(player_id: player_id, faction_id: faction_id)&.faction_score

        appearance.update_columns(
          overall_avg_rank: overall_avg,
          faction_avg_rank: faction_avg,
          perf_score: perf,
          faction_perf_score: faction_perf
        )

        # Add this match's rank to the cumulative stats (for future matches)
        if appearance.contribution_rank.present?
          player_ranks[player_id] << appearance.contribution_rank
          player_faction_ranks[player_id][faction_id] << appearance.contribution_rank
        end
      end

      processed += 1
      puts "Processed #{processed}/#{total} matches" if processed % 100 == 0
    end

    puts "Backfill complete: #{processed} matches processed"
  end

  def down
    # No-op - don't remove data on rollback
  end
end
