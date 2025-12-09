class BackfillApmToAppearances < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    Appearance.includes(:player, match: :wc3stats_replay).find_each do |appearance|
      replay = appearance.match&.wc3stats_replay
      next unless replay&.body

      player = appearance.player
      next unless player

      # Find matching player in replay data
      replay_players = replay.body.dig("data", "game", "players") || []
      replay_player = replay_players.find do |rp|
        rp["name"] == player.battletag ||
          player.alternative_battletags&.include?(rp["name"])
      end

      next unless replay_player && replay_player["apm"]

      appearance.update_column(:apm, replay_player["apm"])
    end
  end

  def down
    # No-op: don't remove data on rollback
  end
end
