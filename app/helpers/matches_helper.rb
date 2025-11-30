module MatchesHelper
  # Calculate win/loss record for a player before this match
  def previous_record_for_appearance(appearance)
    match = appearance.match
    player = appearance.player

    # Get all matches before this one in chronological order
    previous_appearances = player.appearances
      .joins(:match)
      .where(matches: { ignored: false })
      .merge(Match.chronological)
      .includes(:faction, :match)
      .select { |a| match_is_before?(a.match, match) }

    wins = 0
    losses = 0

    previous_appearances.each do |a|
      player_won = (a.faction.good? && a.match.good_victory?) || (!a.faction.good? && !a.match.good_victory?)
      if player_won
        wins += 1
      else
        losses += 1
      end
    end

    "<span class=\"text-green-600\">#{wins}W</span>-<span class=\"text-red-600\">#{losses}L</span>".html_safe
  end

  # Check if match_a comes before match_b chronologically
  def match_is_before?(match_a, match_b)
    return false if match_a.id == match_b.id

    # Compare using the same criteria as the chronological scope
    a_vals = [
      match_a.major_version || 0,
      match_a.build_version || 0,
      match_a.row_order || 999999,
      match_a.map_version || "",
      match_a.uploaded_at || Time.at(0),
      match_a.wc3stats_replay_id || match_a.id
    ]
    b_vals = [
      match_b.major_version || 0,
      match_b.build_version || 0,
      match_b.row_order || 999999,
      match_b.map_version || "",
      match_b.uploaded_at || Time.at(0),
      match_b.wc3stats_replay_id || match_b.id
    ]

    (a_vals <=> b_vals) < 0
  end

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

  def sum_castles_razed(appearances)
    appearances.to_a.sum { |appearance| appearance[:castles_razed].to_i }
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

  def avg_custom_rating(appearances)
    total = appearances.to_a.sum { |appearance| appearance.custom_rating.to_i }
    (total.to_f / appearances.size).round
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

  # Healing stats
  def sum_self_heal(appearances)
    appearances.to_a.sum { |appearance| appearance[:self_heal].to_i }
  end

  def sum_team_heal(appearances)
    appearances.to_a.sum { |appearance| appearance[:team_heal].to_i }
  end

  def sum_total_heal(appearances)
    appearances.to_a.sum { |appearance| appearance[:total_heal].to_i }
  end

  def avg_self_heal(appearances)
    (sum_self_heal(appearances).to_f / appearances.size).round
  end

  def avg_team_heal(appearances)
    (sum_team_heal(appearances).to_f / appearances.size).round
  end

  def avg_total_heal(appearances)
    (sum_total_heal(appearances).to_f / appearances.size).round
  end

  # Healing contribution as percentage of team total
  def heal_contribution(appearance, appearances)
    team_total = sum_total_heal(appearances)
    return "-" if team_total == 0

    player_heal = appearance[:total_heal].to_i
    percentage = (player_heal.to_f / team_total * 100).round(1)
    "#{percentage}%"
  end

  # Team heal contribution (healing others) as percentage of team total team heal
  def team_heal_contribution(appearance, appearances)
    team_total = sum_team_heal(appearances)
    return "-" if team_total == 0

    player_team_heal = appearance[:team_heal].to_i
    percentage = (player_team_heal.to_f / team_total * 100).round(1)
    "#{percentage}%"
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
