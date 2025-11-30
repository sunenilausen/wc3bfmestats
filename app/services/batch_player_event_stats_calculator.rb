# Computes hero and base death statistics for multiple players in a single pass
# This is much more efficient than calling PlayerEventStatsCalculator for each player
class BatchPlayerEventStatsCalculator
  EXTRA_HERO_MAPPING = FactionEventStatsCalculator::EXTRA_HERO_MAPPING
  BONUS_HEROES = FactionEventStatsCalculator::BONUS_HEROES
  EXTRA_HEROES = FactionEventStatsCalculator::EXTRA_HEROES

  def initialize(player_ids)
    @player_ids = player_ids
  end

  def compute
    # Initialize stats for all players
    stats = {}
    @player_ids.each do |player_id|
      stats[player_id] = initialize_player_stats
    end

    # Load players and index by battletag for fast lookup
    players_by_id = Player.where(id: @player_ids).index_by(&:id)
    battletag_to_player_id = players_by_id.transform_values(&:battletag).invert

    # Load all factions for fast lookup
    factions_by_name = Faction.all.index_by(&:name)

    # Only load replays where these players appear (instead of all replays)
    replay_ids = Appearance.joins(:match)
      .where(player_id: @player_ids, matches: { ignored: false })
      .where.not(matches: { wc3stats_replay_id: nil })
      .pluck("matches.wc3stats_replay_id")
      .uniq

    Wc3statsReplay.includes(match: :appearances).where(id: replay_ids).find_each do |replay|
      next unless replay.match.present?
      next if replay.match.ignored?

      match_length = replay.game_length || replay.match.seconds
      next unless match_length && match_length > 0

      # Index appearances by player_id for fast lookup
      appearances_by_player = replay.match.appearances.index_by(&:player_id)

      # Process each player in the replay
      replay.players.each do |player_data|
        battletag = fix_encoding(replay, player_data["name"])
        player_id = battletag_to_player_id[battletag]
        next unless player_id && stats[player_id] # Only process players we care about

        slot = player_data["slot"]
        next unless slot.present? && slot >= 0 && slot <= 9

        faction_name = Wc3stats::MatchBuilder::SLOT_TO_FACTION[slot]
        next unless faction_name

        faction = factions_by_name[faction_name]
        next unless faction

        player_stats = stats[player_id]
        player_stats[:total_games] += 1

        # Get hero kills from appearance data
        appearance = appearances_by_player[player_id]
        hero_kills = appearance&.hero_kills
        has_hero_kills_data = !hero_kills.nil? && !appearance&.ignore_hero_kills?
        player_stats[:hero_kills] += hero_kills if has_hero_kills_data

        hero_names = faction.heroes
        base_names = faction.bases
        core_hero_names = hero_names.reject { |h| EXTRA_HEROES.include?(h) }

        # Process hero deaths if hero kills data is available
        if has_hero_kills_data
          player_stats[:games_with_hero_data] += 1

          # Get hero death events for this match (cached per replay)
          hero_death_events = @hero_death_events_cache ||= {}
          hero_death_events[replay.id] ||= replay.events.select do |e|
            e["eventName"] == "heroDeath" && e["time"] && e["time"] <= match_length
          end

          core_heroes_died = 0
          core_hero_names.each do |hero_name|
            hero_events = hero_death_events[replay.id].select do |event|
              fix_encoding(replay, event["args"]&.first) == hero_name
            end

            if hero_events.any?
              death_time = hero_events.map { |e| e["time"] }.compact.min
              player_stats[:hero_death_times] << death_time if death_time
              player_stats[:total_hero_seconds_alive] += death_time if death_time
              core_heroes_died += 1
              player_stats[:hero_deaths] += 1
            else
              player_stats[:total_hero_seconds_alive] += match_length
            end
            player_stats[:total_hero_seconds_possible] += match_length
          end

          player_stats[:games_all_heroes_survived] += 1 if core_heroes_died == 0 && core_hero_names.any?
          player_stats[:all_heroes_lost_count] += 1 if core_heroes_died == core_hero_names.size && core_hero_names.any?
        end

        # Skip base processing for factions without bases
        next if base_names.empty?

        player_stats[:games_with_bases] += 1

        # Get base death events (cached per replay)
        @base_death_events_cache ||= {}
        @base_death_events_cache[replay.id] ||= begin
          base_events = replay.events.select do |e|
            e["eventName"] != "heroDeath" &&
              !Faction::RING_EVENTS.include?(fix_encoding(replay, e["args"]&.first)) &&
              e["time"] && e["time"] <= match_length
          end
          filter_end_game_deaths(base_events, match_length)
        end

        bases_died = 0
        base_names.each do |base_name|
          base_events = @base_death_events_cache[replay.id].select do |event|
            fix_encoding(replay, event["args"]&.first) == base_name
          end

          if base_events.any?
            death_time = base_events.map { |e| e["time"] }.compact.min
            player_stats[:base_death_times] << death_time if death_time
            player_stats[:total_base_seconds_alive] += death_time if death_time
            bases_died += 1
          else
            player_stats[:total_base_seconds_alive] += match_length
          end
          player_stats[:total_base_seconds_possible] += match_length
        end

        player_stats[:games_all_bases_survived] += 1 if bases_died == 0 && base_names.any?
        player_stats[:all_bases_lost_count] += 1 if bases_died == base_names.size && base_names.any?
      end

      # Clear per-replay caches
      @hero_death_events_cache = {}
      @base_death_events_cache = {}
    end

    # Finalize stats for all players
    stats.transform_values { |s| finalize_stats(s) }
  end

  private

  def initialize_player_stats
    {
      total_games: 0,
      games_with_hero_data: 0,
      hero_kills: 0,
      hero_deaths: 0,
      hero_death_times: [],
      games_all_heroes_survived: 0,
      all_heroes_lost_count: 0,
      total_hero_seconds_alive: 0,
      total_hero_seconds_possible: 0,
      games_with_bases: 0,
      base_death_times: [],
      games_all_bases_survived: 0,
      all_bases_lost_count: 0,
      total_base_seconds_alive: 0,
      total_base_seconds_possible: 0
    }
  end

  def finalize_stats(stats)
    hero_deaths_count = stats[:hero_death_times].size
    games_with_hero_data = stats[:games_with_hero_data]
    games_with_bases = stats[:games_with_bases]

    {
      total_games: stats[:total_games],
      games_with_hero_data: games_with_hero_data,
      hero_kills: stats[:hero_kills],
      hero_deaths: hero_deaths_count,
      hero_kd_ratio: hero_deaths_count > 0 ? (stats[:hero_kills].to_f / hero_deaths_count).round(2) : nil,
      games_all_heroes_survived: stats[:games_all_heroes_survived],
      all_heroes_survived_rate: games_with_hero_data > 0 ? (stats[:games_all_heroes_survived].to_f / games_with_hero_data * 100).round(1) : 0,
      avg_hero_death_time: stats[:hero_death_times].any? ? (stats[:hero_death_times].sum.to_f / stats[:hero_death_times].size).round : nil,
      all_heroes_lost: stats[:all_heroes_lost_count],
      all_heroes_lost_rate: games_with_hero_data > 0 ? (stats[:all_heroes_lost_count].to_f / games_with_hero_data * 100).round(1) : 0,
      hero_uptime: stats[:total_hero_seconds_possible] > 0 ? (stats[:total_hero_seconds_alive].to_f / stats[:total_hero_seconds_possible] * 100).round(1) : 0,
      base_deaths: stats[:base_death_times].size,
      games_with_bases: games_with_bases,
      games_all_bases_survived: stats[:games_all_bases_survived],
      all_bases_survived_rate: games_with_bases > 0 ? (stats[:games_all_bases_survived].to_f / games_with_bases * 100).round(1) : 0,
      avg_base_death_time: stats[:base_death_times].any? ? (stats[:base_death_times].sum.to_f / stats[:base_death_times].size).round : nil,
      all_bases_lost: stats[:all_bases_lost_count],
      all_bases_lost_rate: games_with_bases > 0 ? (stats[:all_bases_lost_count].to_f / games_with_bases * 100).round(1) : 0,
      base_uptime: stats[:total_base_seconds_possible] > 0 ? (stats[:total_base_seconds_alive].to_f / stats[:total_base_seconds_possible] * 100).round(1) : 0
    }
  end

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
