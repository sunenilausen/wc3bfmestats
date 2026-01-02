class BackfillEarlyLeaverData < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Process each match that has a wc3stats_replay
    Match.joins(:wc3stats_replay)
      .includes(:wc3stats_replay, appearances: :player)
      .find_each do |match|
      replay = match.wc3stats_replay
      next unless replay

      # Check if this match has an early leaver
      has_early = replay.has_early_leaver?

      if has_early
        # Update the match
        match.update_column(:has_early_leaver, true)

        # Get the early leaver battletags
        early_leaver_tags = replay.early_leaver_battletags

        # Mark the specific player(s) as early leaver
        match.appearances.each do |appearance|
          player = appearance.player
          next unless player

          # Check if this player's battletag matches any early leaver
          is_leaver = early_leaver_tags.include?(player.battletag) ||
                      (player.alternative_battletags&.any? { |bt| early_leaver_tags.include?(bt) })

          # Also check with encoding fix
          unless is_leaver
            is_leaver = early_leaver_tags.any? do |tag|
              replay.fix_encoding(tag) == player.battletag ||
                player.alternative_battletags&.include?(replay.fix_encoding(tag))
            end
          end

          appearance.update_column(:is_early_leaver, true) if is_leaver
        end
      end
    end
  end

  def down
    Match.update_all(has_early_leaver: false)
    Appearance.update_all(is_early_leaver: false)
  end
end
