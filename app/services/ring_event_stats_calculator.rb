class RingEventStatsCalculator
  attr_reader :faction

  # Ring events mapped to factions
  FACTION_RING_EVENTS = {
    "Fellowship" => "Ring Drop",
    "Mordor" => "Sauron gets the ring"
  }.freeze

  SAURON_HERO_NAME = "Sauron the Great"

  def initialize(faction)
    @faction = faction
  end

  def compute
    ring_event = FACTION_RING_EVENTS[faction.name]
    return nil unless ring_event

    occurrences = []
    total_games = 0

    # Track Sauron deaths after getting the ring (for Mordor only)
    sauron_deaths_after_ring = []

    Wc3statsReplay.includes(:match).find_each do |replay|
      next unless replay.match.present?
      next if replay.match.ignored?

      match_length = replay.game_length || replay.match.seconds
      next unless match_length && match_length > 0

      # Check if this faction was played in this match
      faction_appearance = replay.match.appearances.find { |a| a.faction_id == faction.id }
      next unless faction_appearance

      total_games += 1

      # Find the ring event for this faction
      ring_events = replay.events.select do |e|
        fix_encoding(replay, e["args"]&.first) == ring_event
      end

      if ring_events.any?
        event_time = ring_events.map { |e| e["time"] }.compact.min
        occurrences << event_time if event_time

        # For Mordor, check if Sauron dies after getting the ring
        if faction.name == "Mordor" && event_time
          sauron_death_events = replay.events.select do |e|
            e["eventName"] == "heroDeath" &&
              fix_encoding(replay, e["args"]&.first) == SAURON_HERO_NAME &&
              e["time"] && e["time"] > event_time
          end

          if sauron_death_events.any?
            sauron_death_time = sauron_death_events.map { |e| e["time"] }.compact.min
            time_until_death = sauron_death_time - event_time
            sauron_deaths_after_ring << time_until_death
          end
        end
      end
    end

    return nil if total_games == 0

    occurrence_count = occurrences.size
    occurrence_rate = (occurrence_count.to_f / total_games * 100).round(1)
    avg_time = occurrences.any? ? (occurrences.sum.to_f / occurrence_count).round : nil

    result = {
      name: ring_event,
      total_games: total_games,
      occurrences: occurrence_count,
      occurrence_rate: occurrence_rate,
      avg_time: avg_time
    }

    # Add Sauron death stats for Mordor
    if faction.name == "Mordor" && occurrence_count > 0
      sauron_death_count = sauron_deaths_after_ring.size
      result[:sauron_death_rate] = (sauron_death_count.to_f / occurrence_count * 100).round(1)
      result[:sauron_deaths] = sauron_death_count
      result[:sauron_avg_time_to_death] = sauron_deaths_after_ring.any? ? (sauron_deaths_after_ring.sum.to_f / sauron_death_count).round : nil
    end

    result
  end

  private

  def fix_encoding(replay, str)
    return str if str.nil?
    replay.fix_encoding(str.gsub("\\", ""))
  end
end
