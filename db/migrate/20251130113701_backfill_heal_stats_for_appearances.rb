class BackfillHealStatsForAppearances < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    total = Appearance.joins(match: :wc3stats_replay).count
    updated = 0
    skipped_no_data = 0
    skipped_no_player = 0

    say "Backfilling heal stats for #{total} appearances..."

    Appearance.joins(match: :wc3stats_replay)
      .includes({ match: :wc3stats_replay }, :player)
      .find_each do |appearance|
      replay = appearance.match.wc3stats_replay
      player = appearance.player

      unless replay && player
        skipped_no_player += 1
        next
      end

      # Find the player's data in the replay
      player_data = replay.players.find do |p|
        battletag = p["name"]
        fixed_battletag = replay.fix_encoding(battletag&.gsub("\\", "") || "")
        player.battletag == fixed_battletag || player.battletag == battletag
      end

      unless player_data
        skipped_no_player += 1
        next
      end

      self_heal = player_data.dig("variables", "selfHeal")
      team_heal = player_data.dig("variables", "teamHeal")

      # Skip if replay doesn't have heal data
      unless self_heal || team_heal
        skipped_no_data += 1
        next
      end

      total_heal = (self_heal || 0) + (team_heal || 0)

      changes = {}
      changes[:self_heal] = self_heal if self_heal && appearance.self_heal != self_heal
      changes[:team_heal] = team_heal if team_heal && appearance.team_heal != team_heal
      changes[:total_heal] = total_heal if appearance.total_heal != total_heal

      if changes.any?
        appearance.update_columns(changes)
        updated += 1
      end
    end

    say "Updated: #{updated}, Skipped (no heal data in replay): #{skipped_no_data}, Skipped (player not found): #{skipped_no_player}"
  end

  def down
    # No-op: we don't want to remove the data on rollback
  end
end
