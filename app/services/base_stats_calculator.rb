class BaseStatsCalculator
  attr_reader :faction

  def initialize(faction)
    @faction = faction
  end

  def compute
    base_names = faction.bases
    return [] if base_names.empty?

    # Initialize stats for each base
    stats = base_names.each_with_object({}) do |name, hash|
      hash[name] = { deaths: [], survivals: 0, total_games: 0 }
    end

    # Process all replays in a single pass
    Wc3statsReplay.includes(:match).find_each do |replay|
      next unless replay.match.present?
      next if replay.match.ignored?

      match_length = replay.game_length || replay.match.seconds
      next unless match_length && match_length > 0

      # Check if this faction was played in this match
      faction_appearance = replay.match.appearances.find { |a| a.faction_id == faction.id }
      next unless faction_appearance

      # Get all base death events for this match (excluding hero deaths and ring events)
      base_death_events = replay.events.select do |e|
        e["eventName"] != "heroDeath" && !Faction::RING_EVENTS.include?(fix_encoding(replay, e["args"]&.first))
      end

      # Filter out end-of-game mass deaths (multiple bases dying at nearly the same time at the end)
      filtered_events = filter_end_game_deaths(base_death_events, match_length)

      # Update stats for each base of this faction
      base_names.each do |base_name|
        base_events = filtered_events.select do |event|
          fix_encoding(replay, event["args"]&.first) == base_name
        end

        if base_events.any?
          # Base was destroyed - record time of destruction
          death_time = base_events.map { |e| e["time"] }.compact.min
          stats[base_name][:deaths] << death_time if death_time
          stats[base_name][:total_games] += 1
        else
          # Base survived this match
          stats[base_name][:survivals] += 1
          stats[base_name][:total_games] += 1
        end
      end
    end

    # Calculate final stats
    result = base_names.map do |base_name|
      data = stats[base_name]
      total_games = data[:total_games]
      deaths_count = data[:deaths].size
      survivals = data[:survivals]

      death_rate = total_games > 0 ? (deaths_count.to_f / total_games * 100).round(1) : 0
      avg_time_to_death = data[:deaths].any? ? (data[:deaths].sum.to_f / deaths_count).round : nil

      {
        name: base_name,
        total_games: total_games,
        deaths: deaths_count,
        survivals: survivals,
        death_rate: death_rate,
        avg_time_to_death: avg_time_to_death
      }
    end

    # Sort by death rate ascending (lowest death rate first), then by sample size
    result.sort_by { |s| [ s[:death_rate], -s[:total_games] ] }
  end

  private

  # Filter out end-of-game mass deaths where multiple bases die at nearly the same time
  # This happens when a team loses and all their remaining bases are destroyed
  def filter_end_game_deaths(events, match_length)
    return events if events.empty?

    # Group events by time (within 10 seconds of each other at the end of the match)
    end_threshold = match_length - 30 # Last 30 seconds of the match

    # Find events that happen in the last 30 seconds
    end_game_events = events.select { |e| e["time"] && e["time"] >= end_threshold }

    # If 3 or more bases die in the last 30 seconds, consider it a mass death and exclude them
    if end_game_events.size >= 3
      end_game_times = end_game_events.map { |e| e["time"] }

      # Check if they all died within 15 seconds of each other
      if end_game_times.max - end_game_times.min <= 15
        # Exclude these end-game mass deaths
        return events.reject { |e| e["time"] && e["time"] >= end_threshold }
      end
    end

    events
  end

  def fix_encoding(replay, str)
    return str if str.nil?
    replay.fix_encoding(str.gsub("\\", ""))
  end
end
