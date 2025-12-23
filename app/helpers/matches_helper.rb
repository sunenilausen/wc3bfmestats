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

  def sum_main_base_destroyed(appearances)
    appearances.to_a.sum { |appearance| appearance[:main_base_destroyed].to_i }
  end

  def avg_unit_kills(appearances)
    (sum_unit_kills(appearances).to_f / appearances.size).round(2)
  end

  def avg_hero_kills(appearances)
    (sum_hero_kills(appearances).to_f / appearances.size).round(2)
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

  # Calculate contribution bonus for an appearance
  # Returns hash with :rank (1-5), :bonus (-1 to +3), and :score
  def contribution_bonus_for_appearance(appearance, appearances)
    match = appearance.match

    # No contribution points or MVP for ignored matches
    if match.ignored?
      return { rank: nil, bonus: 0, score: 0, mvp: false, ignored: true }
    end

    # Calculate performance scores for all team members
    ranked = appearances.map do |a|
      { appearance: a, score: performance_score_for_appearance(a, appearances) }
    end.sort_by { |r| -r[:score] }

    rank_index = ranked.index { |r| r[:appearance].id == appearance.id } || (ranked.size - 1)
    team_size = ranked.size

    is_good = appearance.faction.good?
    won = (is_good && match.good_victory?) || (!is_good && !match.good_victory?)

    # Winners: +2, +1, +1, 0, -1 | Losers: +1, +1, 0, -1, -1
    bonus_array = won ? [ 2, 1, 1, 0, -1 ] : [ 1, 1, 0, -1, -1 ]
    bonus = bonus_array[rank_index] || 0

    # Check for MVP (top unit kills AND top hero kills on winning team)
    mvp = false
    if won
      mvp = is_mvp?(appearance, appearances)
      bonus += 1 if mvp
    end

    { rank: rank_index + 1, bonus: bonus, score: ranked[rank_index][:score].round(1), mvp: mvp, ignored: false }
  end

  # Factions that get a 1.33x unit kill multiplier for MVP calculation (support factions)
  MVP_UNIT_KILL_BOOST_FACTIONS = [ "Minas Morgul", "Fellowship" ].freeze
  MVP_UNIT_KILL_BOOST = 1.5

  # Check if player has both top unit kills AND top hero kills on their team
  def is_mvp?(appearance, team_appearances)
    # Check top unit kills (with 1.25x boost for Minas Morgul and Fellowship)
    valid_unit_kills = team_appearances.select { |a| a.unit_kills && !a.ignore_unit_kills? }
    return false unless valid_unit_kills.any?

    adjusted_unit_kills = valid_unit_kills.map do |a|
      base = a.unit_kills
      if MVP_UNIT_KILL_BOOST_FACTIONS.include?(a.faction.name)
        (base * MVP_UNIT_KILL_BOOST).round
      else
        base
      end
    end

    my_unit_kills = appearance.unit_kills
    if appearance.unit_kills && !appearance.ignore_unit_kills? && MVP_UNIT_KILL_BOOST_FACTIONS.include?(appearance.faction.name)
      my_unit_kills = (appearance.unit_kills * MVP_UNIT_KILL_BOOST).round
    end

    max_adjusted_unit_kills = adjusted_unit_kills.max
    has_top_unit_kills = my_unit_kills && my_unit_kills == max_adjusted_unit_kills

    return false unless has_top_unit_kills

    # Check top hero kills (must have strictly more than second place)
    valid_hero_kills = team_appearances.select { |a| a.hero_kills && !a.ignore_hero_kills? }
    return false unless valid_hero_kills.any?

    sorted_hero_kills = valid_hero_kills.map(&:hero_kills).sort.reverse
    max_hero_kills = sorted_hero_kills[0]
    second_hero_kills = sorted_hero_kills[1] || 0

    return false if max_hero_kills == 0
    return false unless appearance.hero_kills && !appearance.ignore_hero_kills?

    # Must have top hero kills AND strictly more than second place
    appearance.hero_kills == max_hero_kills && max_hero_kills > second_hero_kills
  end

  # Calculate performance score (uses same weights as MlScoreRecalculator)
  def performance_score_for_appearance(appearance, team_appearances)
    match = appearance.match
    weights = MlScoreRecalculator::WEIGHTS
    score = 0.0

    # Hero kill contribution (capped at 40% for scoring)
    if appearance.hero_kills && !appearance.ignore_hero_kills?
      team_hero_kills = team_appearances.sum { |a| (a.hero_kills && !a.ignore_hero_kills?) ? a.hero_kills : 0 }
      if team_hero_kills > 0
        hk_contrib = [ (appearance.hero_kills.to_f / team_hero_kills) * 100, 40.0 ].min
        score += (hk_contrib - 20.0) * weights[:hero_kill_contribution]
      end
    end

    # Unit kill contribution (capped at 40% for scoring)
    if appearance.unit_kills && !appearance.ignore_unit_kills?
      team_unit_kills = team_appearances.sum { |a| (a.unit_kills && !a.ignore_unit_kills?) ? a.unit_kills : 0 }
      if team_unit_kills > 0
        uk_contrib = [ (appearance.unit_kills.to_f / team_unit_kills) * 100, 40.0 ].min
        score += (uk_contrib - 20.0) * weights[:unit_kill_contribution]
      end
    end

    # Castle raze contribution (capped at 30% for scoring)
    if appearance.castles_razed
      team_castles = team_appearances.sum { |a| a.castles_razed || 0 }
      if team_castles > 0
        cr_contrib = [ (appearance.castles_razed.to_f / team_castles) * 100, 30.0 ].min
        score += (cr_contrib - 20.0) * weights[:castle_raze_contribution]
      end
    end

    # Team heal contribution (capped at 40% for scoring)
    if appearance.team_heal && appearance.team_heal > 0
      team_heal_total = team_appearances.sum { |a| (a.team_heal && a.team_heal > 0) ? a.team_heal : 0 }
      if team_heal_total > 0
        th_contrib = [ (appearance.team_heal.to_f / team_heal_total) * 100, 40.0 ].min
        score += (th_contrib - 20.0) * weights[:team_heal_contribution]
      end
    end

    # Hero uptime (0-100%)
    hero_uptime = calculate_hero_uptime_for_appearance(appearance, match)
    if hero_uptime
      score += (hero_uptime - 80.0) * weights[:hero_uptime]
    end

    score
  end

  # Check if a player's early leave should be "excused" (not count as a real leave)
  # Excused if:
  # 1. Someone else left before them (they're not first to leave), OR
  # 2. A teammate left within 60 seconds after them (game was ending anyway)
  LEAVE_GRACE_PERIOD = 60 # seconds

  def is_excused_leave?(appearance, match)
    replay = match.wc3stats_replay
    return true unless replay&.body # Can't determine, assume excused

    game_players = replay.body.dig("data", "game", "players")
    return true unless game_players

    player = appearance.player
    return true unless player

    # Find this player in the replay
    player_data = find_player_in_replay_data(game_players, player, replay)
    return true unless player_data

    my_left_at = player_data["leftAt"]
    return true unless my_left_at # No leave time, assume stayed

    my_team = player_data["team"]

    # Get all non-observer players with leave times
    all_players_with_leave = game_players.reject { |p| p["isObserver"] }
                                          .select { |p| p["leftAt"].present? }
                                          .sort_by { |p| p["leftAt"] }

    return true if all_players_with_leave.empty?

    # Check if someone left before this player
    first_leave_time = all_players_with_leave.first["leftAt"]
    return true if my_left_at > first_leave_time # Not the first to leave

    # Check if a teammate left within grace period after this player
    teammates = all_players_with_leave.select { |p| p["team"] == my_team && p["leftAt"] > my_left_at }
    teammate_left_soon = teammates.any? { |p| p["leftAt"] - my_left_at <= LEAVE_GRACE_PERIOD }
    return true if teammate_left_soon

    false # This is a real leave
  end

  def find_player_in_replay_data(game_players, player, replay)
    game_players.find do |p|
      battletag = p["name"]
      next unless battletag
      fixed_battletag = replay.fix_encoding(battletag.gsub("\\", ""))
      player.battletag == fixed_battletag || player.battletag == battletag ||
        player.alternative_battletags&.include?(fixed_battletag) ||
        player.alternative_battletags&.include?(battletag)
    end
  end

  # Calculate hero uptime for an appearance from replay events
  def calculate_hero_uptime_for_appearance(appearance, match)
    replay = match.wc3stats_replay
    return nil unless replay&.events&.any?

    faction = appearance.faction
    return nil unless faction

    match_length = replay.game_length || match.seconds
    return nil unless match_length && match_length > 0

    # Get core hero names (exclude extra heroes like Sauron)
    extra_heroes = FactionEventStatsCalculator::EXTRA_HEROES rescue []
    core_hero_names = faction.heroes.reject { |h| extra_heroes.include?(h) }
    return nil if core_hero_names.empty?

    # Get hero death events within match length
    hero_death_events = replay.events.select do |e|
      e["eventName"] == "heroDeath" && e["time"] && e["time"] <= match_length
    end

    total_seconds_alive = 0
    total_seconds_possible = 0

    core_hero_names.each do |hero_name|
      hero_events = hero_death_events.select do |event|
        replay.fix_encoding(event["args"]&.first&.gsub("\\", "")) == hero_name
      end

      if hero_events.any?
        death_time = hero_events.map { |e| e["time"] }.compact.min
        total_seconds_alive += death_time if death_time
      else
        total_seconds_alive += match_length
      end
      total_seconds_possible += match_length
    end

    return nil if total_seconds_possible == 0

    (total_seconds_alive.to_f / total_seconds_possible * 100).round(1)
  end
end
