class BackfillStayPctOnAppearances < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    Appearance.joins(match: :wc3stats_replay)
      .includes({ match: :wc3stats_replay }, :player, :faction)
      .find_each do |appearance|
      replay = appearance.match.wc3stats_replay
      next unless replay&.body

      player = appearance.player
      next unless player

      # Find player in replay data
      game_players = replay.body.dig("data", "game", "players")
      next unless game_players

      player_data = game_players.find do |p|
        battletag = p["name"]
        next unless battletag
        fixed_battletag = replay.fix_encoding(battletag.gsub("\\", ""))
        player.battletag == fixed_battletag || player.battletag == battletag ||
          player.alternative_battletags&.include?(fixed_battletag) ||
          player.alternative_battletags&.include?(battletag)
      end

      if player_data && player_data["stayPercent"]
        appearance.update_column(:stay_pct, player_data["stayPercent"])
      end
    end
  end

  def down
    # No-op: don't remove data on rollback
  end
end
