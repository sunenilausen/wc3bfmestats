class FactionEventStatsCalculator
  attr_reader :faction, :map_version, :map_versions, :limit

  FACTION_RING_EVENTS = {
    "Fellowship" => "Ring Drop",
    "Mordor" => "Sauron gets the ring",
    "Isengard" => "Saruman takes the ring for himself"
  }.freeze

  # The form a hero takes once they have the ring. Dying in this form is what we
  # can see afterwards - there is no event for the transformation itself, only
  # for the death. Note Isengard's trigger only exists in 4.6+, so before that
  # the death is the only trace of Saruman having taken the ring at all.
  RING_HERO = {
    "Mordor" => "Sauron the Great",
    "Isengard" => "Saruman the Terrible"
  }.freeze

  # A ring event is rare enough for some factions that the individual games are
  # more useful than the percentage. Listed only while there are few enough to
  # read - Mordor's few hundred would be noise, and would bloat the cached stats.
  RING_MATCH_LIST_MAX = 30

  # Factions that also report whether they were left with no bases at all in a
  # game where they took the ring - Isengard can end up playing solo, and those
  # games are worth being able to pick out rather than folding into the ratings.
  # Isengard only; Mordor's Barad-Dur/Morannon rows were not wanted.
  RING_BASE_DEATH_FACTIONS = [ "Isengard" ].freeze

  # Hero first names mapped to factions (for "[Hero] uses the ring" events in 4.6+)
  # These are extracted from hero full names to match the event format
  RINGBEARER_HERO_TO_FACTION = {
    # Gondor
    "Faramir" => "Gondor",
    "Denethor" => "Gondor",
    "Beregond" => "Gondor",
    "Anborn" => "Gondor",
    "Hirluin" => "Gondor",
    # Rohan
    "Théoden" => "Rohan",
    "Eómer" => "Rohan",
    "Eowyn" => "Rohan",
    "Gamling" => "Rohan",
    "Grimbold" => "Rohan",
    # Dol Amroth
    "Imrahil" => "Dol Amroth",
    "Forlong" => "Dol Amroth",
    "Duinhir" => "Dol Amroth",
    "Corinir" => "Dol Amroth",
    # Fellowship
    "Gandalf" => "Fellowship",
    "Aragorn" => "Fellowship",
    "Boromir" => "Fellowship",
    "Frodo" => "Fellowship",
    "Samwise" => "Fellowship",
    "Sam" => "Fellowship",
    "Meriadoc" => "Fellowship",
    "Merry" => "Fellowship",
    "Peregrin" => "Fellowship",
    "Pippin" => "Fellowship",
    "Legolas" => "Fellowship",
    "Gimli" => "Fellowship",
    # Fangorn
    "Treebeard" => "Fangorn",
    "Galadriel" => "Fangorn",
    "Celeborn" => "Fangorn",
    "Haldir" => "Fangorn",
    # Isengard (Saruman has special event)
    "Saruman" => "Isengard",
    "Grima" => "Isengard",
    "Lurtz" => "Isengard",
    "Úgluk" => "Isengard",
    "Ugluk" => "Isengard",
    "Sharkû" => "Isengard",
    "Sharku" => "Isengard",
    # Easterlings
    "Ovatha" => "Easterlings",
    "Gwaer" => "Easterlings",
    "Kurgath" => "Easterlings",
    "Zuldân" => "Easterlings",
    "Zuldan" => "Easterlings",
    # Harad
    "Suladân" => "Harad",
    "Suladan" => "Harad",
    "Carycyn" => "Harad",
    "Husâjek" => "Harad",
    "Husajek" => "Harad",
    "Owynvan" => "Harad",
    # Minas Morgul (Nazgul - using common names)
    "Er-Murâzor" => "Minas Morgul",
    "Witch-King" => "Minas Morgul",
    "Adûnaphel" => "Minas Morgul",
    "Akhôrahil" => "Minas Morgul",
    "Dwar" => "Minas Morgul",
    "Hoarmûrath" => "Minas Morgul",
    "Jí Indûr" => "Minas Morgul",
    "Ji Indur" => "Minas Morgul",
    "Ren" => "Minas Morgul",
    "Khamûl" => "Minas Morgul",
    "Khamul" => "Minas Morgul",
    "Ûvatha" => "Minas Morgul",
    "Uvatha" => "Minas Morgul",
    # Mordor
    "Sauron" => "Mordor",
    "Mouth" => "Mordor",
    "Gothmog" => "Mordor",
    "Shagrat" => "Mordor",
    "Bâdruík" => "Mordor",
    "Badruik" => "Mordor"
  }.freeze

  # Minimum map version for ringbearer events (they were added in 4.6)
  RINGBEARER_MIN_VERSION = "4.6"

  # Some ring triggers only exist from a given map version. Isengard's was added
  # in 4.6 - before that the map fired nothing when Saruman took the ring, so
  # counting those games in the denominator would understate the rate rather
  # than measure it. Mordor's and Fellowship's go back to 4.0, so they count
  # every game.
  RING_EVENT_MIN_VERSION = { "Isengard" => "4.6" }.freeze

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

  def initialize(faction, map_version: nil, map_versions: nil, limit: nil)
    @faction = faction
    @map_version = map_version
    @map_versions = map_versions
    @limit = limit
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
    ring_hero_deaths_after_ring = []
    ring_losses = 0
    ring_eligible_games = 0
    ring_games_without_bases = 0
    ring_last_base_deaths = []
    ring_matches = []
    legacy_matches = []

    # Before the trigger existed, the ringbearer form dying is the only surviving
    # evidence that the ring was ever taken. Counted separately so it is never
    # mistaken for the real trigger rate.
    legacy_games = 0
    legacy_deaths = []
    legacy_deaths_without_bases = 0
    legacy_losses = 0
    all_bases_lost_times = []
    all_heroes_lost_times = []
    all_heroes_lost_twice_times = [] # For Minas Morgul
    total_games = 0

    # Ringbearer tracking (4.6+ only)
    ringbearer_occurrences = []  # Times when a hero from this faction became ringbearer
    ringbearer_heroes = Hash.new(0)  # Count per hero
    ringbearer_games = 0  # Games that are 4.6+

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
    elsif map_versions.present?
      replay_query = replay_query.where(matches: { map_version: map_versions })
    end

    # Apply limit if specified (most recent games first)
    if limit.present? && limit > 0
      replay_query = replay_query.merge(Match.reverse_chronological).limit(limit)
    end

    replay_ids = replay_query.pluck("matches.wc3stats_replay_id").uniq

    Wc3statsReplay.includes(match: { appearances: :faction }).where(id: replay_ids).find_each do |replay|
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

      # Games from before this faction's trigger was added to the map
      if ring_event && RING_HERO[faction.name] && replay.map_version.present? &&
         !ring_event_possible?(replay.map_version)
        legacy_games += 1

        death = hero_death_events
          .select { |e| fix_encoding(replay, e["args"]&.first) == RING_HERO[faction.name] }
          .filter_map { |e| e["time"] }.min

        if death
          legacy_deaths << death
          legacy_matches << match_reference(replay, faction_appearance, death)
          legacy_losses += 1 if faction_lost?(replay.match)
          all_bases_dead = base_names.all? do |base_name|
            base_death_events.any? { |e| fix_encoding(replay, e["args"]&.first) == base_name }
          end
          legacy_deaths_without_bases += 1 if all_bases_dead
        end
      end

      # Process ring events
      if ring_event && ring_event_possible?(replay.map_version)
        ring_eligible_games += 1
        ring_events_in_match = replay.events.select do |e|
          fix_encoding(replay, e["args"]&.first) == ring_event
        end

        if ring_events_in_match.any?
          event_time = ring_events_in_match.map { |e| e["time"] }.compact.min
          ring_occurrences << event_time if event_time

          # Did taking the ring save them? Counted per ring event, not per game.
          ring_matches << match_reference(replay, faction_appearance, event_time)
          ring_losses += 1 if faction_lost?(replay.match)

          # Track the ringbearer form dying after the ring was taken
          ring_hero = RING_HERO[faction.name]
          if ring_hero && event_time
            ring_hero_death_events = hero_death_events.select do |e|
              fix_encoding(replay, e["args"]&.first) == ring_hero &&
                e["time"] && e["time"] > event_time
            end

            if ring_hero_death_events.any?
              death_time = ring_hero_death_events.map { |e| e["time"] }.compact.min
              ring_hero_deaths_after_ring << (death_time - event_time)
            end
          end

          # Were they left with nothing? Read as the state of the game, not as a
          # consequence of the ring - a base lost before the ring was taken
          # counts just the same, since what matters is whether they ended up
          # with no bases at all. Unfiltered deaths for the same reason: a base
          # that fell in the closing collapse is still gone.
          if event_time && ring_base_deaths_reported?
            death_times = base_names.map do |base_name|
              base_death_events
                .select { |e| fix_encoding(replay, e["args"]&.first) == base_name }
                .filter_map { |e| e["time"] }.min
            end

            if death_times.all?
              ring_games_without_bases += 1
              ring_last_base_deaths << (death_times.max - event_time)
            end
          end
        end
      end

      # Process ringbearer events (4.6+ only)
      if version_at_least?(replay.map_version, RINGBEARER_MIN_VERSION)
        ringbearer_games += 1

        # Find "[Hero] uses the ring" and "Saruman takes the ring for himself"
        # events, skipping this faction's own ring trigger - Isengard's is both,
        # and reporting it here as well would just repeat the Ring Events table.
        ringbearer_events_in_match = replay.events.select do |e|
          next false unless e["eventName"] == "eventsTriggered"
          event_text = fix_encoding(replay, e["args"]&.first)
          next false unless event_text
          next false if event_text == ring_event

          # Match "[Hero] uses the ring" or "Saruman takes the ring for himself"
          event_text.match?(/uses the ring\z/i) || event_text == "Saruman takes the ring for himself"
        end

        ringbearer_events_in_match.each do |event|
          event_text = fix_encoding(replay, event["args"]&.first)
          hero_name = extract_ringbearer_hero(event_text)
          next unless hero_name

          # Check if this hero belongs to the current faction
          hero_faction = RINGBEARER_HERO_TO_FACTION[hero_name]
          next unless hero_faction == faction.name

          event_time = event["time"]
          ringbearer_occurrences << event_time if event_time
          ringbearer_heroes[hero_name] += 1
        end
      end
    end

    # Build results
    {
      base_stats: build_base_results(base_names, base_stats),
      base_loss_stats: build_base_loss_results(base_names, total_games, all_bases_lost_times),
      hero_stats: build_hero_results(display_hero_names, hero_stats),
      hero_loss_stats: build_hero_loss_results(core_hero_names, total_games, all_heroes_lost_times, all_heroes_lost_twice_times),
      ring_event_stats: build_ring_results(ring_event, ring_eligible_games, ring_occurrences,
                                           ring_hero_deaths_after_ring, ring_losses,
                                           ring_games_without_bases, ring_last_base_deaths, ring_matches),
      legacy_ring_stats: build_legacy_ring_results(legacy_games, legacy_deaths, legacy_deaths_without_bases,
                                                   legacy_losses, legacy_matches),
      ringbearer_stats: build_ringbearer_results(ringbearer_games, ringbearer_occurrences, ringbearer_heroes),
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

  def build_ring_results(ring_event, eligible_games, occurrences, ring_hero_deaths_after_ring, ring_losses,
                         ring_games_without_bases, ring_last_base_deaths, ring_matches)
    return nil unless ring_event
    return nil if eligible_games == 0

    occurrence_count = occurrences.size
    result = {
      name: ring_event,
      total_games: eligible_games,
      min_version: RING_EVENT_MIN_VERSION[faction.name],
      occurrences: occurrence_count,
      occurrence_rate: (occurrence_count.to_f / eligible_games * 100).round(1),
      avg_time: occurrences.any? ? (occurrences.sum.to_f / occurrence_count).round : nil
    }
    return result if occurrence_count.zero?

    # What became of the ringbearer, for the factions whose hero transforms
    ring_hero = RING_HERO[faction.name]
    if ring_hero
      death_count = ring_hero_deaths_after_ring.size
      result[:ring_hero_name] = ring_hero.split(" ").first
      result[:ring_hero_death_rate] = (death_count.to_f / occurrence_count * 100).round(1)
      result[:ring_hero_deaths] = death_count
      result[:ring_hero_avg_time_to_death] =
        ring_hero_deaths_after_ring.any? ? (ring_hero_deaths_after_ring.sum.to_f / death_count).round : nil
    end

    # Left with no bases at all - the games where Isengard ends up solo
    if ring_base_deaths_reported?
      result[:no_bases_label] = "#{faction.bases.join(" and ")} dies"
      result[:no_bases_count] = ring_games_without_bases
      result[:no_bases_rate] = (ring_games_without_bases.to_f / occurrence_count * 100).round(1)
      result[:no_bases_avg_time] =
        ring_last_base_deaths.any? ? (ring_last_base_deaths.sum.to_f / ring_last_base_deaths.size).round : nil
    end

    # And whether taking the ring actually won the game
    result[:loss_label] = faction.good? ? "Good loses" : "Evil loses"
    result[:loss_rate] = (ring_losses.to_f / occurrence_count * 100).round(1)
    result[:losses] = ring_losses
    result[:matches] = listable_matches(ring_matches)

    result
  end

  # The games themselves, when there are few enough to be worth reading
  def listable_matches(matches)
    return nil if matches.empty? || matches.size > RING_MATCH_LIST_MAX

    matches.sort_by { |m| m[:played_at] || Time.at(0) }.reverse
  end

  def match_reference(replay, faction_appearance, event_time)
    match = replay.match
    {
      id: match.id,
      param: replay.replay_hash || match.id.to_s,
      played_at: match.played_at || match.uploaded_at,
      map_version: replay.map_version,
      player_id: faction_appearance&.player_id,
      won: !faction_lost?(match) && !match.is_draw?,
      draw: match.is_draw?,
      event_time: event_time,
      seconds: match.seconds
    }
  end

  # What we can still see of the ring in games played before the trigger existed:
  # the ringbearer form dying proves he took it, and the bases being gone as well
  # says he took it and lost anyway.
  def build_legacy_ring_results(games, deaths, deaths_without_bases, losses, matches)
    return nil if games.zero? || deaths.empty?

    death_count = deaths.size
    {
      hero_name: RING_HERO[faction.name],
      before_version: RING_EVENT_MIN_VERSION[faction.name],
      total_games: games,
      deaths: death_count,
      death_rate: (death_count.to_f / games * 100).round(1),
      avg_time: (deaths.sum.to_f / death_count).round,
      bases_label: "#{faction.bases.join(" and ")} dies",
      bases_count: deaths_without_bases,
      bases_rate: (deaths_without_bases.to_f / death_count * 100).round(1),
      loss_label: faction.good? ? "Good loses" : "Evil loses",
      losses: losses,
      loss_rate: (losses.to_f / death_count * 100).round(1),
      matches: listable_matches(matches)
    }
  end

  def ring_base_deaths_reported?
    RING_BASE_DEATH_FACTIONS.include?(faction.name)
  end

  # Whether the map fired this faction's ring trigger at all in this version
  def ring_event_possible?(map_version)
    minimum = RING_EVENT_MIN_VERSION[faction.name]
    return true if minimum.nil?

    version_at_least?(map_version, minimum)
  end

  # Did the side this faction plays for lose the match?
  def faction_lost?(match)
    return false if match.nil? || match.is_draw?

    faction.good? ? !match.good_victory? : match.good_victory?
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

  def build_ringbearer_results(total_games, occurrences, heroes)
    return nil if total_games == 0

    occurrence_count = occurrences.size
    return nil if occurrence_count == 0

    # Sort heroes by count (descending)
    sorted_heroes = heroes.sort_by { |_, count| -count }.to_h

    {
      total_games: total_games,
      occurrences: occurrence_count,
      occurrence_rate: (occurrence_count.to_f / total_games * 100).round(1),
      avg_time: occurrences.any? ? (occurrences.sum.to_f / occurrence_count).round : nil,
      heroes: sorted_heroes
    }
  end

  # Compare version strings (e.g., "4.6" >= "4.6", "4.5e" < "4.6")
  def version_at_least?(version, min_version)
    return false if version.nil? || min_version.nil?

    # Extract numeric parts (e.g., "4.5e" -> [4, 5], "4.6" -> [4, 6])
    v_parts = version.scan(/\d+/).map(&:to_i)
    min_parts = min_version.scan(/\d+/).map(&:to_i)

    # Compare each part
    max_length = [ v_parts.length, min_parts.length ].max
    max_length.times do |i|
      v = v_parts[i] || 0
      m = min_parts[i] || 0
      return true if v > m
      return false if v < m
    end

    true # Equal versions
  end

  # Extract hero name from ringbearer event text
  # "[Hero] uses the ring" -> "Hero"
  # "Saruman takes the ring for himself" -> "Saruman"
  def extract_ringbearer_hero(event_text)
    return nil if event_text.nil?

    if event_text == "Saruman takes the ring for himself"
      "Saruman"
    elsif event_text.match?(/uses the ring\z/i)
      # Extract hero name before " uses the ring"
      event_text.sub(/ uses the ring\z/i, "").strip
    end
  end
end
