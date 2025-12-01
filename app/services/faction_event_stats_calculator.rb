class FactionEventStatsCalculator
  attr_reader :faction, :map_version

  SAURON_HERO_NAME = "Sauron the Great"

  FACTION_RING_EVENTS = {
    "Fellowship" => "Ring Drop",
    "Mordor" => "Sauron gets the ring"
  }.freeze

  # Extra heroes mapped to their original hero form
  EXTRA_HERO_MAPPING = {
    "Sauron the Great" => nil, # Sauron has no base form, exclude from stats
    "Saruman the Terrible" => "Saruman of Many Colors",
    "Denethor the Tainted" => "Denethor son of Ecthelion",
    "Gandalf the Sorcerer" => "Gandalf the White",
    "King Elessar" => "Aragorn son of Arathorn"
  }.freeze

  # Extra heroes that are new heroes (not transformations) - excluded from "all starting heroes"
  BONUS_HEROES = [ "Grimbold the Twisted" ].freeze

  EXTRA_HEROES = (EXTRA_HERO_MAPPING.keys + BONUS_HEROES).freeze

  # Faction with heroes that can die twice (Nazgul)
  MULTI_LIFE_FACTION = "Minas Morgul"

  def initialize(faction, map_version: nil)
    @faction = faction
    @map_version = map_version
  end

  def compute
    base_names = faction.bases
    hero_names = faction.heroes
    core_hero_names = hero_names.reject { |h| EXTRA_HEROES.include?(h) }
    ring_event = FACTION_RING_EVENTS[faction.name]

    # Initialize all stats
    base_stats = base_names.each_with_object({}) do |name, hash|
      hash[name] = { deaths: [], survivals: 0, total_games: 0 }
    end

    # Filter out transformed heroes (they'll be merged with their base form)
    # Keep bonus heroes (like Grimbold) as separate entries
    display_hero_names = hero_names.reject { |h| EXTRA_HERO_MAPPING.key?(h) }

    hero_stats = display_hero_names.each_with_object({}) do |name, hash|
      hash[name] = { deaths: [], second_deaths: [], survivals: 0, total_games: 0, extra_deaths: 0, bonus: BONUS_HEROES.include?(name) }
    end

    ring_occurrences = []
    sauron_deaths_after_ring = []
    all_bases_lost_times = []
    all_heroes_lost_times = []
    all_heroes_lost_twice_times = [] # For Minas Morgul
    total_games = 0

    # Uptime tracking
    total_hero_seconds_alive = 0
    total_hero_seconds_possible = 0
    total_base_seconds_alive = 0
    total_base_seconds_possible = 0

    # Hero K/D tracking
    total_hero_kills = 0
    total_hero_deaths = 0

    # Only load replays where this faction was played (instead of all replays)
    replay_query = Appearance.joins(:match)
      .where(faction_id: faction.id, matches: { ignored: false })
      .where.not(matches: { wc3stats_replay_id: nil })

    if map_version.present?
      replay_query = replay_query.where(matches: { map_version: map_version })
    end

    replay_ids = replay_query.pluck("matches.wc3stats_replay_id").uniq

    Wc3statsReplay.includes(match: :appearances).where(id: replay_ids).find_each do |replay|
      next unless replay.match.present?

      match_length = replay.game_length || replay.match.seconds
      next unless match_length && match_length > 0

      # Get the faction appearance (we know it exists since we filtered by faction)
      faction_appearance = replay.match.appearances.find { |a| a.faction_id == faction.id }
      next unless faction_appearance

      total_games += 1

      # Track hero kills from appearance (for K/D ratio)
      if !faction_appearance.hero_kills.nil? && !faction_appearance.ignore_hero_kills?
        total_hero_kills += faction_appearance.hero_kills
      end

      # Get all events categorized, filtering out post-game deaths
      hero_death_events = replay.events.select do |e|
        e["eventName"] == "heroDeath" && e["time"] && e["time"] <= match_length
      end
      base_death_events = replay.events.select do |e|
        e["eventName"] != "heroDeath" &&
          !Faction::RING_EVENTS.include?(fix_encoding(replay, e["args"]&.first)) &&
          e["time"] && e["time"] <= match_length
      end

      # Filter end-game mass base deaths
      filtered_base_events = filter_end_game_deaths(base_death_events, match_length)

      # Process base stats
      base_death_times = {}
      base_names.each do |base_name|
        base_events = filtered_base_events.select do |event|
          fix_encoding(replay, event["args"]&.first) == base_name
        end

        if base_events.any?
          death_time = base_events.map { |e| e["time"] }.compact.min
          base_stats[base_name][:deaths] << death_time if death_time
          base_stats[base_name][:total_games] += 1
          base_death_times[base_name] = death_time
          # Track uptime: time alive before death
          total_base_seconds_alive += death_time if death_time
        else
          base_stats[base_name][:survivals] += 1
          base_stats[base_name][:total_games] += 1
          # Base survived entire match
          total_base_seconds_alive += match_length
        end
        total_base_seconds_possible += match_length
      end

      # Track all bases lost
      if base_names.any? && base_death_times.size == base_names.size && base_death_times.values.all?
        all_bases_lost_times << base_death_times.values.max
      end

      # Process hero stats (display heroes only, transformed heroes merged in)
      core_hero_death_times = {}
      core_hero_second_death_times = {} # For Minas Morgul
      display_hero_names.each do |hero_name|
        # Find deaths for this hero
        hero_events = hero_death_events.select do |event|
          fix_encoding(replay, event["args"]&.first) == hero_name
        end

        # Find deaths for transformed form of this hero (if any)
        transformed_hero_name = EXTRA_HERO_MAPPING.key(hero_name)
        transformed_hero_events = if transformed_hero_name
          hero_death_events.select do |event|
            fix_encoding(replay, event["args"]&.first) == transformed_hero_name
          end
        else
          []
        end

        if hero_events.any? || transformed_hero_events.any?
          death_times = hero_events.map { |e| e["time"] }.compact.sort
          first_death_time = death_times.first

          if first_death_time
            hero_stats[hero_name][:deaths] << first_death_time
          end
          hero_stats[hero_name][:total_games] += 1

          # Count transformed hero deaths
          if transformed_hero_events.any?
            hero_stats[hero_name][:extra_deaths] += 1
          end

          # Track second death for multi-life heroes (Nazgul)
          if faction.name == MULTI_LIFE_FACTION && death_times.size >= 2
            second_death_time = death_times[1]
            hero_stats[hero_name][:second_deaths] << second_death_time

            # Track for "all heroes lost twice"
            if core_hero_names.include?(hero_name)
              core_hero_second_death_times[hero_name] = second_death_time
            end
          end

          # Track core hero deaths for "all heroes lost" (exclude bonus heroes)
          if core_hero_names.include?(hero_name) && first_death_time
            core_hero_death_times[hero_name] = first_death_time
            total_hero_deaths += 1
          end

          # Track uptime for core heroes only
          if core_hero_names.include?(hero_name)
            total_hero_seconds_alive += first_death_time if first_death_time
            total_hero_seconds_alive += match_length unless first_death_time
            total_hero_seconds_possible += match_length
          end
        else
          hero_stats[hero_name][:survivals] += 1
          hero_stats[hero_name][:total_games] += 1

          # Track uptime for core heroes only (survived entire match)
          if core_hero_names.include?(hero_name)
            total_hero_seconds_alive += match_length
            total_hero_seconds_possible += match_length
          end
        end
      end

      # Track all core heroes lost
      if core_hero_names.any? && core_hero_death_times.size == core_hero_names.size && core_hero_death_times.values.all?
        all_heroes_lost_times << core_hero_death_times.values.max
      end

      # Track all core heroes lost twice (Minas Morgul only)
      if faction.name == MULTI_LIFE_FACTION && core_hero_names.any? &&
         core_hero_second_death_times.size == core_hero_names.size && core_hero_second_death_times.values.all?
        all_heroes_lost_twice_times << core_hero_second_death_times.values.max
      end

      # Process ring events
      if ring_event
        ring_events_in_match = replay.events.select do |e|
          fix_encoding(replay, e["args"]&.first) == ring_event
        end

        if ring_events_in_match.any?
          event_time = ring_events_in_match.map { |e| e["time"] }.compact.min
          ring_occurrences << event_time if event_time

          # Track Sauron death after getting ring (Mordor only)
          if faction.name == "Mordor" && event_time
            sauron_death_events = hero_death_events.select do |e|
              fix_encoding(replay, e["args"]&.first) == SAURON_HERO_NAME &&
                e["time"] && e["time"] > event_time
            end

            if sauron_death_events.any?
              sauron_death_time = sauron_death_events.map { |e| e["time"] }.compact.min
              sauron_deaths_after_ring << (sauron_death_time - event_time)
            end
          end
        end
      end
    end

    # Build results
    {
      base_stats: build_base_results(base_names, base_stats),
      base_loss_stats: build_base_loss_results(base_names, total_games, all_bases_lost_times),
      hero_stats: build_hero_results(display_hero_names, hero_stats),
      hero_loss_stats: build_hero_loss_results(core_hero_names, total_games, all_heroes_lost_times, all_heroes_lost_twice_times),
      ring_event_stats: build_ring_results(ring_event, total_games, ring_occurrences, sauron_deaths_after_ring),
      hero_uptime: total_hero_seconds_possible > 0 ? (total_hero_seconds_alive.to_f / total_hero_seconds_possible * 100).round(1) : 0,
      base_uptime: total_base_seconds_possible > 0 ? (total_base_seconds_alive.to_f / total_base_seconds_possible * 100).round(1) : 0,
      hero_kills: total_hero_kills,
      hero_deaths: total_hero_deaths,
      hero_kd_ratio: total_hero_deaths > 0 ? (total_hero_kills.to_f / total_hero_deaths).round(2) : nil
    }
  end

  private

  def build_base_results(base_names, stats)
    result = base_names.map do |base_name|
      data = stats[base_name]
      total = data[:total_games]
      deaths_count = data[:deaths].size

      {
        name: base_name,
        total_games: total,
        deaths: deaths_count,
        survivals: data[:survivals],
        death_rate: total > 0 ? (deaths_count.to_f / total * 100).round(1) : 0,
        avg_time_to_death: data[:deaths].any? ? (data[:deaths].sum.to_f / deaths_count).round : nil
      }
    end

    result.sort_by { |s| [ s[:death_rate], -s[:total_games] ] }
  end

  def build_base_loss_results(base_names, total_games, all_bases_lost_times)
    return nil if base_names.empty? || total_games == 0

    count = all_bases_lost_times.size
    {
      total_games: total_games,
      all_bases_lost: count,
      all_bases_lost_rate: (count.to_f / total_games * 100).round(1),
      avg_time_to_lose_all: all_bases_lost_times.any? ? (all_bases_lost_times.sum.to_f / count).round : nil
    }
  end

  def build_hero_results(display_hero_names, stats)
    result = display_hero_names.map do |hero_name|
      data = stats[hero_name]
      total = data[:total_games]
      deaths_count = data[:deaths].size
      extra_deaths_count = data[:extra_deaths]
      second_deaths_count = data[:second_deaths].size

      hero_result = {
        name: hero_name,
        total_games: total,
        deaths: deaths_count,
        extra_deaths: extra_deaths_count,
        survivals: data[:survivals],
        death_rate: total > 0 ? (deaths_count.to_f / total * 100).round(1) : 0,
        avg_time_to_death: data[:deaths].any? ? (data[:deaths].sum.to_f / deaths_count).round : nil,
        bonus: data[:bonus]
      }

      # Add second death stats for multi-life heroes
      if faction.name == MULTI_LIFE_FACTION && deaths_count > 0
        hero_result[:second_deaths] = second_deaths_count
        hero_result[:second_death_rate] = (second_deaths_count.to_f / deaths_count * 100).round(1)
        hero_result[:avg_time_to_second_death] = data[:second_deaths].any? ? (data[:second_deaths].sum.to_f / second_deaths_count).round : nil
      end

      hero_result
    end

    result.sort_by { |s| [ s[:death_rate], -s[:total_games] ] }
  end

  def build_hero_loss_results(core_hero_names, total_games, all_heroes_lost_times, all_heroes_lost_twice_times)
    return nil if core_hero_names.empty? || total_games == 0

    count = all_heroes_lost_times.size
    result = {
      total_games: total_games,
      all_heroes_lost: count,
      all_heroes_lost_rate: (count.to_f / total_games * 100).round(1),
      avg_time_to_lose_all: all_heroes_lost_times.any? ? (all_heroes_lost_times.sum.to_f / count).round : nil
    }

    # Add "all heroes lost twice" stats for Minas Morgul
    if faction.name == MULTI_LIFE_FACTION && count > 0
      twice_count = all_heroes_lost_twice_times.size
      result[:all_heroes_lost_twice] = twice_count
      result[:all_heroes_lost_twice_rate] = (twice_count.to_f / count * 100).round(1)
      result[:avg_time_to_lose_all_twice] = all_heroes_lost_twice_times.any? ? (all_heroes_lost_twice_times.sum.to_f / twice_count).round : nil
    end

    result
  end

  def build_ring_results(ring_event, total_games, occurrences, sauron_deaths_after_ring)
    return nil unless ring_event
    return nil if total_games == 0

    occurrence_count = occurrences.size
    result = {
      name: ring_event,
      total_games: total_games,
      occurrences: occurrence_count,
      occurrence_rate: (occurrence_count.to_f / total_games * 100).round(1),
      avg_time: occurrences.any? ? (occurrences.sum.to_f / occurrence_count).round : nil
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
