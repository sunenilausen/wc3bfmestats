class BackfillMainBaseDestroyedFromReplayData < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Map slot positions to faction names (same as MatchBuilder)
  SLOT_TO_FACTION = {
    0 => "Gondor",
    1 => "Rohan",
    2 => "Dol Amroth",
    3 => "Fellowship",
    4 => "Fangorn",
    5 => "Isengard",
    6 => "Easterlings",
    7 => "Harad",
    8 => "Minas Morgul",
    9 => "Mordor"
  }.freeze

  def up
    factions_by_name = Faction.all.index_by(&:name)

    Appearance.includes(:faction, match: :wc3stats_replay).find_each do |appearance|
      replay = appearance.match&.wc3stats_replay
      next unless replay.present?

      faction = appearance.faction
      next unless faction

      # Find the slot for this faction
      slot = SLOT_TO_FACTION.key(faction.name)
      next unless slot

      # Find the player data for this slot
      player_data = replay.players.find { |p| p["slot"] == slot }
      next unless player_data

      main_base_destroyed = player_data.dig("variables", "mainBaseDestroyed")
      if main_base_destroyed.present?
        appearance.update_column(:main_base_destroyed, main_base_destroyed)
      end
    end
  end

  def down
    Appearance.update_all(main_base_destroyed: nil)
  end
end
