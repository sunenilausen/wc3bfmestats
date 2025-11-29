# Computes hero and base death statistics for a player across all their matches
class PlayerEventStatsCalculator
  attr_reader :player

  # Extra heroes mapped to their original hero form
  EXTRA_HERO_MAPPING = FactionEventStatsCalculator::EXTRA_HERO_MAPPING
  BONUS_HEROES = FactionEventStatsCalculator::BONUS_HEROES
  EXTRA_HEROES = FactionEventStatsCalculator::EXTRA_HEROES

  def initialize(player)
    @player = player
  end

  def compute
    hero_death_times = []
    base_death_times = []
    total_games = 0
    games_all_heroes_survived = 0
    games_all_bases_survived = 0
    all_heroes_lost_count = 0
    all_bases_lost_count = 0
    heroes_survived_per_game = []
    heroes_total_per_game = []
    bases_survived_per_game = []
    bases_total_per_game = []
    total_hero_seconds_alive = 0
    total_hero_seconds_possible = 0
    total_base_seconds_alive = 0
    total_base_seconds_possible = 0
    games_with_bases = 0
    games_with_hero_data = 0
    total_hero_kills = 0
    total_hero_deaths = 0

    # Per-faction stats
    faction_stats = Hash.new do |h, k|
      h[k] = {
        hero_kills: 0,
        hero_deaths: 0,
        hero_seconds_alive: 0,
        hero_seconds_possible: 0,
        base_seconds_alive: 0,
        base_seconds_possible: 0,
        games_with_hero_data: 0,
        games_with_bases: 0
      }
    end

    # Get all replays where this player participated in non-ignored matches
    Wc3statsReplay.includes(match: :appearances).find_each do |replay|
      next unless replay.match.present?
      next if replay.match.ignored?

      match_length = replay.game_length || replay.match.seconds
      next unless match_length && match_length > 0

      # Find this player in the replay
      player_data = replay.players.find do |p|
        fix_encoding(replay, p["name"]) == player.battletag
      end
      next unless player_data

      slot = player_data["slot"]
      next unless slot.present? && slot >= 0 && slot <= 9

      # Determine which faction this player played
      faction_name = Wc3stats::MatchBuilder::SLOT_TO_FACTION[slot]
      next unless faction_name

      faction = Faction.find_by(name: faction_name)
      next unless faction

      total_games += 1

      # Get hero kills from appearance data - only process hero stats if hero kills data exists
      appearance = replay.match.appearances.find { |a| a.player_id == player.id }
      hero_kills = appearance&.hero_kills
      has_hero_kills_data = !hero_kills.nil? && !appearance&.ignore_hero_kills?
      total_hero_kills += hero_kills if has_hero_kills_data

      hero_names = faction.heroes
      base_names = faction.bases
      core_hero_names = hero_names.reject { |h| EXTRA_HEROES.include?(h) }

      # Only process hero deaths if hero kills data is available (skip games where hero kills aren't working)
      if has_hero_kills_data
        games_with_hero_data += 1
        faction_stats[faction.id][:games_with_hero_data] += 1
        faction_stats[faction.id][:hero_kills] += hero_kills

        # Get hero death events for this faction's heroes
        hero_death_events = replay.events.select do |e|
          e["eventName"] == "heroDeath" && e["time"] && e["time"] <= match_length
        end

        # Process hero deaths for this player's faction
        core_heroes_died = 0

        core_hero_names.each do |hero_name|
          hero_events = hero_death_events.select do |event|
            fix_encoding(replay, event["args"]&.first) == hero_name
          end

          # Track uptime: time alive before first death (or full match if survived)
          if hero_events.any?
            death_time = hero_events.map { |e| e["time"] }.compact.min
            hero_death_times << death_time if death_time
            total_hero_seconds_alive += death_time if death_time
            faction_stats[faction.id][:hero_seconds_alive] += death_time if death_time
            core_heroes_died += 1
            total_hero_deaths += 1
            faction_stats[faction.id][:hero_deaths] += 1
          else
            total_hero_seconds_alive += match_length
            faction_stats[faction.id][:hero_seconds_alive] += match_length
          end
          total_hero_seconds_possible += match_length
          faction_stats[faction.id][:hero_seconds_possible] += match_length
        end

        games_all_heroes_survived += 1 if core_heroes_died == 0 && core_hero_names.any?
        all_heroes_lost_count += 1 if core_heroes_died == core_hero_names.size && core_hero_names.any?
        if core_hero_names.any?
          heroes_survived_per_game << (core_hero_names.size - core_heroes_died)
          heroes_total_per_game << core_hero_names.size
        end
      end

      # Get base death events
      base_death_events = replay.events.select do |e|
        e["eventName"] != "heroDeath" &&
          !Faction::RING_EVENTS.include?(fix_encoding(replay, e["args"]&.first)) &&
          e["time"] && e["time"] <= match_length
      end

      # Filter end-game mass base deaths
      filtered_base_events = filter_end_game_deaths(base_death_events, match_length)

      # Process base deaths for this player's faction (skip factions without bases like Fellowship)
      next if base_names.empty?

      games_with_bases += 1
      faction_stats[faction.id][:games_with_bases] += 1
      bases_died = 0

      base_names.each do |base_name|
        base_events = filtered_base_events.select do |event|
          fix_encoding(replay, event["args"]&.first) == base_name
        end

        # Track uptime: time alive before first death (or full match if survived)
        if base_events.any?
          death_time = base_events.map { |e| e["time"] }.compact.min
          base_death_times << death_time if death_time
          total_base_seconds_alive += death_time if death_time
          faction_stats[faction.id][:base_seconds_alive] += death_time if death_time
          bases_died += 1
        else
          total_base_seconds_alive += match_length
          faction_stats[faction.id][:base_seconds_alive] += match_length
        end
        total_base_seconds_possible += match_length
        faction_stats[faction.id][:base_seconds_possible] += match_length
      end

      games_all_bases_survived += 1 if bases_died == 0 && base_names.any?
      all_bases_lost_count += 1 if bases_died == base_names.size && base_names.any?
      if base_names.any?
        bases_survived_per_game << (base_names.size - bases_died)
        bases_total_per_game << base_names.size
      end
    end

    hero_deaths_count = hero_death_times.size

    # Compute per-faction derived stats
    computed_faction_stats = {}
    faction_stats.each do |faction_id, fs|
      computed_faction_stats[faction_id] = {
        hero_kills: fs[:hero_kills],
        hero_deaths: fs[:hero_deaths],
        hero_kd_ratio: fs[:hero_deaths] > 0 ? (fs[:hero_kills].to_f / fs[:hero_deaths]).round(2) : nil,
        hero_uptime: fs[:hero_seconds_possible] > 0 ? (fs[:hero_seconds_alive].to_f / fs[:hero_seconds_possible] * 100).round(1) : 0,
        base_uptime: fs[:base_seconds_possible] > 0 ? (fs[:base_seconds_alive].to_f / fs[:base_seconds_possible] * 100).round(1) : 0,
        games_with_hero_data: fs[:games_with_hero_data],
        games_with_bases: fs[:games_with_bases]
      }
    end

    {
      total_games: total_games,
      games_with_hero_data: games_with_hero_data,
      hero_kills: total_hero_kills,
      hero_deaths: hero_deaths_count,
      hero_kd_ratio: hero_deaths_count > 0 ? (total_hero_kills.to_f / hero_deaths_count).round(2) : nil,
      games_all_heroes_survived: games_all_heroes_survived,
      all_heroes_survived_rate: games_with_hero_data > 0 ? (games_all_heroes_survived.to_f / games_with_hero_data * 100).round(1) : 0,
      avg_hero_death_time: hero_death_times.any? ? (hero_death_times.sum.to_f / hero_death_times.size).round : nil,
      all_heroes_lost: all_heroes_lost_count,
      all_heroes_lost_rate: games_with_hero_data > 0 ? (all_heroes_lost_count.to_f / games_with_hero_data * 100).round(1) : 0,
      avg_heroes_survived: heroes_survived_per_game.any? ? (heroes_survived_per_game.sum.to_f / heroes_survived_per_game.size).round(1) : 0,
      avg_heroes_total: heroes_total_per_game.any? ? (heroes_total_per_game.sum.to_f / heroes_total_per_game.size).round(1) : 0,
      hero_uptime: total_hero_seconds_possible > 0 ? (total_hero_seconds_alive.to_f / total_hero_seconds_possible * 100).round(1) : 0,
      base_deaths: base_death_times.size,
      games_with_bases: games_with_bases,
      games_all_bases_survived: games_all_bases_survived,
      all_bases_survived_rate: games_with_bases > 0 ? (games_all_bases_survived.to_f / games_with_bases * 100).round(1) : 0,
      avg_base_death_time: base_death_times.any? ? (base_death_times.sum.to_f / base_death_times.size).round : nil,
      all_bases_lost: all_bases_lost_count,
      all_bases_lost_rate: games_with_bases > 0 ? (all_bases_lost_count.to_f / games_with_bases * 100).round(1) : 0,
      avg_bases_survived: bases_survived_per_game.any? ? (bases_survived_per_game.sum.to_f / bases_survived_per_game.size).round(1) : 0,
      avg_bases_total: bases_total_per_game.any? ? (bases_total_per_game.sum.to_f / bases_total_per_game.size).round(1) : 0,
      base_uptime: total_base_seconds_possible > 0 ? (total_base_seconds_alive.to_f / total_base_seconds_possible * 100).round(1) : 0,
      faction_stats: computed_faction_stats
    }
  end

  private

  def filter_end_game_deaths(events, match_length)
    return events if events.empty?

    end_threshold = match_length - 30
    end_game_events = events.select { |e| e["time"] && e["time"] >= end_threshold }

    if end_game_events.size >= 3
      end_game_times = end_game_events.map { |e| e["time"] }
      if end_game_times.max - end_game_times.min <= 15
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
