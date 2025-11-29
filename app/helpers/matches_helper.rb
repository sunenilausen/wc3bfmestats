module MatchesHelper
  def sort_link_for(column, label)
    current_sort = params[:sort] == column
    current_direction = params[:direction] || "desc"
    new_direction = current_sort && current_direction == "desc" ? "asc" : "desc"

    arrow = if current_sort
      current_direction == "asc" ? "▲" : "▼"
    else
      ""
    end

    link_to "#{label} #{arrow}".strip, matches_path(sort: column, direction: new_direction),
            class: "text-sm font-medium #{current_sort ? 'text-blue-600' : 'text-gray-600'} hover:text-blue-600"
  end

  def sum_unit_kills(appearances)
    appearances.to_a.sum { |appearance| appearance[:unit_kills].to_i }
  end

  def sum_hero_kills(appearances)
    appearances.to_a.sum { |appearance| appearance[:hero_kills].to_i }
  end

  def avg_unit_kills(appearances)
    (sum_unit_kills(appearances).to_f / appearances.size).round(2)
  end

  def avg_hero_kills(appearances)
    (sum_hero_kills(appearances).to_f / appearances.size).round(2)
  end

  def avg_elo_rating(appearances)
    total_elo = appearances.to_a.sum { |appearance| appearance.elo_rating.to_i }
    (total_elo.to_f / appearances.size).round
  end

  def per_minute_unit_kills(appearances)
    total_seconds = appearances.first.match.seconds.to_f
    return 0 if total_seconds.zero?

    (sum_unit_kills(appearances) * 60 / total_seconds).round(2)
  end

  def per_minute_hero_kills(appearances)
    total_seconds = appearances.first.match.seconds.to_f
    return 0 if total_seconds.zero?

    (sum_hero_kills(appearances) * 60 / total_seconds).round(2)
  end

  # Calculate heroes lost for an appearance based on replay events
  def heroes_lost_for_appearance(appearance)
    replay = appearance.match.wc3stats_replay
    return nil unless replay&.events&.any?

    faction = appearance.faction
    return nil unless faction

    match_length = replay.game_length || appearance.match.seconds
    return nil unless match_length && match_length > 0

    # Get core hero names (exclude extra heroes like Sauron)
    extra_heroes = FactionEventStatsCalculator::EXTRA_HEROES rescue []
    core_hero_names = faction.heroes.reject { |h| extra_heroes.include?(h) }

    # Get hero death events within match length
    hero_death_events = replay.events.select do |e|
      e["eventName"] == "heroDeath" && e["time"] && e["time"] <= match_length
    end

    # Count how many of this faction's heroes died
    heroes_died = 0
    core_hero_names.each do |hero_name|
      hero_events = hero_death_events.select do |event|
        replay.fix_encoding(event["args"]&.first&.gsub("\\", "")) == hero_name
      end
      heroes_died += 1 if hero_events.any?
    end

    "#{heroes_died}/#{core_hero_names.size}"
  end

  # Calculate bases lost for an appearance based on replay events
  def bases_lost_for_appearance(appearance)
    replay = appearance.match.wc3stats_replay
    return nil unless replay&.events&.any?

    faction = appearance.faction
    return nil unless faction

    base_names = faction.bases
    return nil if base_names.empty? # Fellowship has no bases

    match_length = replay.game_length || appearance.match.seconds
    return nil unless match_length && match_length > 0

    # Get base death events (non-hero deaths, excluding ring events)
    ring_events = Faction::RING_EVENTS rescue []
    base_death_events = replay.events.select do |e|
      e["eventName"] != "heroDeath" &&
        !ring_events.include?(replay.fix_encoding(e["args"]&.first&.gsub("\\", ""))) &&
        e["time"] && e["time"] <= match_length
    end

    # Filter end-game mass base deaths
    end_threshold = match_length - 30
    end_game_events = base_death_events.select { |e| e["time"] && e["time"] >= end_threshold }
    if end_game_events.size >= 3
      end_game_times = end_game_events.map { |e| e["time"] }
      if end_game_times.max - end_game_times.min <= 15
        base_death_events = base_death_events.reject { |e| e["time"] && e["time"] >= end_threshold }
      end
    end

    # Count how many of this faction's bases died
    bases_died = 0
    base_names.each do |base_name|
      base_events = base_death_events.select do |event|
        replay.fix_encoding(event["args"]&.first&.gsub("\\", "")) == base_name
      end
      bases_died += 1 if base_events.any?
    end

    "#{bases_died}/#{base_names.size}"
  end
end
