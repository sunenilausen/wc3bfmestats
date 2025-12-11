# Backfills APM data for appearances from replay data
#
# APM (Actions Per Minute) is stored in the replay player data and needs to be
# copied to the appearance record. This handles both initial backfill and
# ongoing updates for appearances missing APM data.
#
class ApmBackfiller
  attr_reader :updated_count, :skipped_count, :errors

  def initialize
    @updated_count = 0
    @skipped_count = 0
    @errors = []
  end

  def call
    backfill_missing_apm
    self
  end

  private

  def backfill_missing_apm
    # Only process appearances that have no APM set and have a replay
    appearances_missing_apm = Appearance
      .where(apm: nil)
      .joins(match: :wc3stats_replay)
      .includes({ match: :wc3stats_replay }, :player)

    appearances_missing_apm.find_each do |appearance|
      process_appearance(appearance)
    rescue StandardError => e
      @errors << "Appearance ##{appearance.id}: #{e.message}"
    end
  end

  def process_appearance(appearance)
    replay = appearance.match&.wc3stats_replay
    return skip unless replay&.body

    player = appearance.player
    return skip unless player

    # Find matching player in replay data
    replay_players = replay.body.dig("data", "game", "players") || []
    replay_player = find_player_in_replay(replay_players, player, replay)

    return skip unless replay_player && replay_player["apm"]

    appearance.update_column(:apm, replay_player["apm"])
    @updated_count += 1
  end

  def find_player_in_replay(replay_players, player, replay)
    replay_players.find do |rp|
      battletag = rp["name"]
      next unless battletag

      fixed_battletag = replay.fix_encoding(battletag.gsub("\\", ""))
      player.battletag == fixed_battletag ||
        player.battletag == battletag ||
        player.alternative_battletags&.include?(fixed_battletag) ||
        player.alternative_battletags&.include?(battletag)
    end
  end

  def skip
    @skipped_count += 1
    nil
  end
end
