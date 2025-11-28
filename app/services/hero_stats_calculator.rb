class HeroStatsCalculator
  attr_reader :faction

  def initialize(faction)
    @faction = faction
  end

  def compute
    hero_names = faction.heroes
    return [] if hero_names.empty?

    # Initialize stats for each hero
    stats = hero_names.each_with_object({}) do |name, hash|
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

      # Get all hero death events for this match
      hero_death_events = replay.events.select { |e| e["eventName"] == "heroDeath" }
      dead_heroes_in_match = hero_death_events.map do |event|
        fix_encoding(replay, event["args"]&.first)
      end.compact

      # Update stats for each hero of this faction
      hero_names.each do |hero_name|
        hero_events = hero_death_events.select do |event|
          fix_encoding(replay, event["args"]&.first) == hero_name
        end

        if hero_events.any?
          # Hero died - record time of first death
          first_death_time = hero_events.map { |e| e["time"] }.compact.min
          stats[hero_name][:deaths] << first_death_time if first_death_time
          stats[hero_name][:total_games] += 1
        else
          # Hero survived this match
          stats[hero_name][:survivals] += 1
          stats[hero_name][:total_games] += 1
        end
      end
    end

    # Calculate final stats
    result = hero_names.map do |hero_name|
      data = stats[hero_name]
      total_games = data[:total_games]
      deaths_count = data[:deaths].size
      survivals = data[:survivals]

      death_rate = total_games > 0 ? (deaths_count.to_f / total_games * 100).round(1) : 0
      avg_time_to_death = data[:deaths].any? ? (data[:deaths].sum.to_f / deaths_count).round : nil

      {
        name: hero_name,
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

  def fix_encoding(replay, str)
    return str if str.nil?
    replay.fix_encoding(str.gsub("\\", ""))
  end
end
