# Computes all player statistics in a single pass over the data
# to avoid N+1 queries and repeated iterations
class PlayerStatsCalculator
  attr_reader :player, :appearances

  def initialize(player, appearances)
    @player = player
    @appearances = appearances
  end

  def compute
    stats = {
      total_matches: 0,
      wins: 0,
      losses: 0,
      wins_as_good: 0,
      losses_as_good: 0,
      wins_as_evil: 0,
      losses_as_evil: 0,
      wins_as_underdog: 0,
      losses_as_underdog: 0,
      wins_as_favorite: 0,
      losses_as_favorite: 0,
      underdog_elo_diffs: [],
      favorite_elo_diffs: [],
      enemy_elo_diffs: [],
      ally_elo_diffs: [],
      times_top_hero_kills: 0,
      times_top_unit_kills: 0,
      times_mvp: 0,
      hero_kill_contributions: [],
      unit_kill_contributions: [],
      castle_raze_contributions: [],
      castles_razed_values: [],
      heal_contributions: [],
      team_heal_contributions: [],
      contribution_ranks: [],
      faction_stats: Hash.new { |h, k| h[k] = new_faction_stats }
    }

    appearances.each do |appearance|
      process_appearance(appearance, stats)
    end

    finalize_stats(stats)
  end

  private

  def new_faction_stats
    {
      games: 0,
      wins: 0,
      losses: 0,
      times_top_hero_kills: 0,
      times_top_unit_kills: 0,
      times_mvp: 0,
      hero_kill_contributions: [],
      unit_kill_contributions: [],
      castle_raze_contributions: [],
      castles_razed_values: [],
      heal_contributions: [],
      team_heal_contributions: [],
      contribution_ranks: []
    }
  end

  def process_appearance(appearance, stats)
    match = appearance.match
    faction = appearance.faction
    player_good = faction.good?
    faction_id = faction.id

    stats[:total_matches] += 1
    stats[:faction_stats][faction_id][:games] += 1

    # Get team and opponent appearances from preloaded data
    all_appearances = match.appearances
    team_appearances = all_appearances.select { |a| a.faction.good? == player_good }
    opponent_appearances = all_appearances.select { |a| a.faction.good? != player_good }

    # Win/loss calculation
    player_won = (player_good && match.good_victory?) || (!player_good && !match.good_victory?)

    if player_won
      stats[:wins] += 1
      stats[:faction_stats][faction_id][:wins] += 1
      if player_good
        stats[:wins_as_good] += 1
      else
        stats[:wins_as_evil] += 1
      end
    else
      stats[:losses] += 1
      stats[:faction_stats][faction_id][:losses] += 1
      if player_good
        stats[:losses_as_good] += 1
      else
        stats[:losses_as_evil] += 1
      end
    end

    # Underdog/favorite calculation
    process_cr_stats(appearance, team_appearances, opponent_appearances, player_won, stats)

    # Kill stats and MVP
    process_kill_stats(appearance, team_appearances, player_won, match, stats, faction_id)

    # Castles razed contribution
    process_castle_stats(appearance, team_appearances, stats, faction_id)

    # Healing contribution
    process_heal_stats(appearance, team_appearances, stats, faction_id)

    # Contribution rank
    process_contribution_rank(appearance, team_appearances, match, stats, faction_id)
  end

  def process_cr_stats(appearance, team_appearances, opponent_appearances, player_won, stats)
    return unless appearance.custom_rating

    team_with_cr = team_appearances.select { |a| a.custom_rating.present? }
    opponents_with_cr = opponent_appearances.select { |a| a.custom_rating.present? }

    return if team_with_cr.empty? || opponents_with_cr.empty?

    player_cr = appearance.custom_rating
    team_avg_cr = team_with_cr.sum(&:custom_rating).to_f / team_with_cr.size
    opponent_avg_cr = opponents_with_cr.sum(&:custom_rating).to_f / opponents_with_cr.size

    # Track player's CR vs enemy team avg (positive = playing against weaker opponents)
    stats[:enemy_elo_diffs] << (player_cr - opponent_avg_cr)

    # Track player's CR vs own team avg (positive = carrying weaker teammates)
    # Exclude self from team average for this calculation
    teammates_with_cr = team_with_cr.reject { |a| a.id == appearance.id }
    if teammates_with_cr.any?
      teammates_avg_cr = teammates_with_cr.sum(&:custom_rating).to_f / teammates_with_cr.size
      stats[:ally_elo_diffs] << (player_cr - teammates_avg_cr)
    end

    cr_diff = (team_avg_cr - opponent_avg_cr).abs
    is_underdog = team_avg_cr < opponent_avg_cr

    if is_underdog
      stats[:underdog_elo_diffs] << cr_diff
      if player_won
        stats[:wins_as_underdog] += 1
      else
        stats[:losses_as_underdog] += 1
      end
    else
      stats[:favorite_elo_diffs] << cr_diff
      if player_won
        stats[:wins_as_favorite] += 1
      else
        stats[:losses_as_favorite] += 1
      end
    end
  end

  # Factions that get a 1.33x unit kill multiplier for MVP calculation (support factions)
  MVP_UNIT_KILL_BOOST_FACTIONS = [ "Minas Morgul", "Fellowship" ].freeze
  MVP_UNIT_KILL_BOOST = 1.5

  def process_kill_stats(appearance, team_appearances, player_won, match, stats, faction_id)
    faction_stats = stats[:faction_stats][faction_id]

    # Hero kills - use stored values if available
    if appearance.hero_kill_pct
      stats[:hero_kill_contributions] << appearance.hero_kill_pct
      faction_stats[:hero_kill_contributions] << appearance.hero_kill_pct
    elsif !appearance.hero_kills.nil? && !appearance.ignore_hero_kills?
      # Fallback: calculate if not stored (no cap - raw percentage for display)
      team_with_hero_kills = team_appearances.select { |a| !a.hero_kills.nil? && !a.ignore_hero_kills? }
      if team_with_hero_kills.any?
        team_total = team_with_hero_kills.sum(&:hero_kills)
        if team_total > 0
          contribution = (appearance.hero_kills.to_f / team_total * 100)
          stats[:hero_kill_contributions] << contribution
          faction_stats[:hero_kill_contributions] << contribution
        end
      end
    end

    # Top hero kills - use stored flag if available, otherwise calculate with tie-sharing
    if appearance.top_hero_kills?
      # When stored, we count ties separately so just add 1
      # However we need to handle tie-sharing for backwards compatibility
      team_with_hero_kills = team_appearances.select { |a| !a.hero_kills.nil? && !a.ignore_hero_kills? }
      if team_with_hero_kills.any?
        max_hero_kills = team_with_hero_kills.map(&:hero_kills).max
        tied_count = team_with_hero_kills.count { |a| a.top_hero_kills? }
        tied_count = 1 if tied_count == 0 # Fallback if flags not yet populated
        share = 1.0 / tied_count
        stats[:times_top_hero_kills] += share
        faction_stats[:times_top_hero_kills] += share
      else
        stats[:times_top_hero_kills] += 1
        faction_stats[:times_top_hero_kills] += 1
      end
    elsif !appearance.hero_kills.nil? && !appearance.ignore_hero_kills? && appearance.top_hero_kills.nil?
      # Fallback: calculate if flag not stored (for backwards compatibility)
      team_with_hero_kills = team_appearances.select { |a| !a.hero_kills.nil? && !a.ignore_hero_kills? }
      if team_with_hero_kills.any?
        max_hero_kills = team_with_hero_kills.map(&:hero_kills).max
        if appearance.hero_kills == max_hero_kills && max_hero_kills > 0
          tied_count = team_with_hero_kills.count { |a| a.hero_kills == max_hero_kills }
          share = 1.0 / tied_count
          stats[:times_top_hero_kills] += share
          faction_stats[:times_top_hero_kills] += share
        end
      end
    end

    # Unit kills - use stored values if available
    if appearance.unit_kill_pct
      stats[:unit_kill_contributions] << appearance.unit_kill_pct
      faction_stats[:unit_kill_contributions] << appearance.unit_kill_pct
    elsif appearance.unit_kills.present? && !appearance.ignore_unit_kills?
      # Fallback: calculate if not stored
      team_with_unit_kills = team_appearances.select { |a| a.unit_kills.present? && !a.ignore_unit_kills? }
      if team_with_unit_kills.any?
        team_total = team_with_unit_kills.sum(&:unit_kills)
        if team_total > 0
          contribution = (appearance.unit_kills.to_f / team_total * 100)
          stats[:unit_kill_contributions] << contribution
          faction_stats[:unit_kill_contributions] << contribution
        end
      end
    end

    # Top unit kills - use stored flag if available, otherwise calculate with tie-sharing
    if appearance.top_unit_kills?
      # When stored, we count ties separately so just add 1
      team_with_unit_kills = team_appearances.select { |a| a.unit_kills.present? && !a.ignore_unit_kills? }
      if team_with_unit_kills.any?
        tied_count = team_with_unit_kills.count { |a| a.top_unit_kills? }
        tied_count = 1 if tied_count == 0 # Fallback if flags not yet populated
        share = 1.0 / tied_count
        stats[:times_top_unit_kills] += share
        faction_stats[:times_top_unit_kills] += share
      else
        stats[:times_top_unit_kills] += 1
        faction_stats[:times_top_unit_kills] += 1
      end
    elsif appearance.unit_kills.present? && !appearance.ignore_unit_kills? && appearance.top_unit_kills.nil?
      # Fallback: calculate if flag not stored (for backwards compatibility)
      team_with_unit_kills = team_appearances.select { |a| a.unit_kills.present? && !a.ignore_unit_kills? }
      if team_with_unit_kills.any?
        max_unit_kills = team_with_unit_kills.map(&:unit_kills).max
        if appearance.unit_kills == max_unit_kills
          tied_count = team_with_unit_kills.count { |a| a.unit_kills == max_unit_kills }
          share = 1.0 / tied_count
          stats[:times_top_unit_kills] += share
          faction_stats[:times_top_unit_kills] += share
        end
      end
    end

    # MVP: use stored is_mvp field (set by CustomRatingRecalculator)
    if appearance.is_mvp?
      stats[:times_mvp] += 1
      faction_stats[:times_mvp] += 1
    end
  end

  def process_castle_stats(appearance, team_appearances, stats, faction_id)
    return unless appearance.castles_razed.present?

    faction_stats = stats[:faction_stats][faction_id]
    stats[:castles_razed_values] << appearance.castles_razed
    faction_stats[:castles_razed_values] << appearance.castles_razed

    # Use stored percentage if available
    if appearance.castle_raze_pct
      stats[:castle_raze_contributions] << appearance.castle_raze_pct
      faction_stats[:castle_raze_contributions] << appearance.castle_raze_pct
    else
      # Fallback: calculate if not stored
      team_with_castles = team_appearances.select { |a| a.castles_razed.present? }
      if team_with_castles.any?
        team_total = team_with_castles.sum(&:castles_razed)
        if team_total > 0
          contribution = (appearance.castles_razed.to_f / team_total * 100)
          stats[:castle_raze_contributions] << contribution
          faction_stats[:castle_raze_contributions] << contribution
        end
      end
    end
  end

  def process_heal_stats(appearance, team_appearances, stats, faction_id)
    faction_stats = stats[:faction_stats][faction_id]

    # Total heal contribution - use stored percentage if available
    if appearance.heal_pct
      stats[:heal_contributions] << appearance.heal_pct
      faction_stats[:heal_contributions] << appearance.heal_pct
    elsif appearance.total_heal.present? && appearance.total_heal > 0
      # Fallback: calculate if not stored
      team_with_heal = team_appearances.select { |a| a.total_heal.present? && a.total_heal > 0 }
      if team_with_heal.any?
        team_total = team_with_heal.sum(&:total_heal)
        if team_total > 0
          contribution = (appearance.total_heal.to_f / team_total * 100)
          stats[:heal_contributions] << contribution
          faction_stats[:heal_contributions] << contribution
        end
      end
    end

    # Team heal contribution - use stored percentage if available
    if appearance.team_heal_pct
      stats[:team_heal_contributions] << appearance.team_heal_pct
      faction_stats[:team_heal_contributions] << appearance.team_heal_pct
    elsif appearance.team_heal.present? && appearance.team_heal > 0
      # Fallback: calculate if not stored
      team_with_team_heal = team_appearances.select { |a| a.team_heal.present? && a.team_heal > 0 }
      if team_with_team_heal.any?
        team_total = team_with_team_heal.sum(&:team_heal)
        if team_total > 0
          contribution = (appearance.team_heal.to_f / team_total * 100)
          stats[:team_heal_contributions] << contribution
          faction_stats[:team_heal_contributions] << contribution
        end
      end
    end
  end

  def process_contribution_rank(appearance, team_appearances, match, stats, faction_id)
    # Use stored contribution_rank if available (set by CustomRatingRecalculator)
    if appearance.contribution_rank
      stats[:contribution_ranks] << appearance.contribution_rank
      stats[:faction_stats][faction_id][:contribution_ranks] << appearance.contribution_rank
      return
    end

    # Fallback: calculate if not stored (for backwards compatibility)
    return if team_appearances.size < 2

    ranked = team_appearances.map do |a|
      { appearance: a, score: performance_score(a, team_appearances, match) }
    end.sort_by { |r| -r[:score] }

    rank = ranked.index { |r| r[:appearance].id == appearance.id }
    return unless rank

    stats[:contribution_ranks] << (rank + 1)
    stats[:faction_stats][faction_id][:contribution_ranks] << (rank + 1)
  end

  # Performance score calculation (uses same weights as MlScoreRecalculator)
  def performance_score(appearance, team_appearances, match)
    weights = MlScoreRecalculator::WEIGHTS
    score = 0.0

    # Hero kill contribution (capped at 20% per hero killed, max 40%)
    if appearance.hero_kills && !appearance.ignore_hero_kills?
      team_hero_kills = team_appearances.sum { |a| (a.hero_kills && !a.ignore_hero_kills?) ? a.hero_kills : 0 }
      if team_hero_kills > 0
        raw_contrib = (appearance.hero_kills.to_f / team_hero_kills) * 100
        max_contrib_by_kills = appearance.hero_kills * 20.0
        hk_contrib = [raw_contrib, max_contrib_by_kills, 40.0].min
        score += (hk_contrib - 20.0) * weights[:hero_kill_contribution]
      end
    end

    # Unit kill contribution (capped at 40%)
    if appearance.unit_kills && !appearance.ignore_unit_kills?
      team_unit_kills = team_appearances.sum { |a| (a.unit_kills && !a.ignore_unit_kills?) ? a.unit_kills : 0 }
      if team_unit_kills > 0
        uk_contrib = [(appearance.unit_kills.to_f / team_unit_kills) * 100, 40.0].min
        score += (uk_contrib - 20.0) * weights[:unit_kill_contribution]
      end
    end

    # Castle raze contribution (capped at 30%)
    if appearance.castles_razed
      team_castles = team_appearances.sum { |a| a.castles_razed || 0 }
      if team_castles > 0
        cr_contrib = [(appearance.castles_razed.to_f / team_castles) * 100, 30.0].min
        score += (cr_contrib - 20.0) * weights[:castle_raze_contribution]
      end
    end

    # Team heal contribution (capped at 40%)
    if appearance.team_heal && appearance.team_heal > 0
      team_heal_total = team_appearances.sum { |a| (a.team_heal && a.team_heal > 0) ? a.team_heal : 0 }
      if team_heal_total > 0
        th_contrib = [(appearance.team_heal.to_f / team_heal_total) * 100, 40.0].min
        score += (th_contrib - 20.0) * weights[:team_heal_contribution]
      end
    end

    # Hero uptime
    hero_uptime = calculate_hero_uptime(appearance, match)
    if hero_uptime
      score += (hero_uptime - 80.0) * weights[:hero_uptime]
    end

    score
  end

  def calculate_hero_uptime(appearance, match)
    replay = match.wc3stats_replay
    return nil unless replay&.events&.any?

    faction = appearance.faction
    return nil unless faction

    match_length = replay.game_length || match.seconds
    return nil unless match_length && match_length > 0

    extra_heroes = FactionEventStatsCalculator::EXTRA_HEROES rescue []
    core_hero_names = faction.heroes.reject { |h| extra_heroes.include?(h) }
    return nil if core_hero_names.empty?

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

  def finalize_stats(stats)
    # Compute averages
    stats[:avg_underdog_elo_diff] = average(stats[:underdog_elo_diffs]).round(0)
    stats[:avg_favorite_elo_diff] = average(stats[:favorite_elo_diffs]).round(0)
    stats[:avg_enemy_elo_diff] = average(stats[:enemy_elo_diffs]).round(0)
    stats[:avg_ally_elo_diff] = average(stats[:ally_elo_diffs]).round(0)
    stats[:avg_hero_kill_contribution] = average(stats[:hero_kill_contributions]).round(1)
    stats[:avg_unit_kill_contribution] = average(stats[:unit_kill_contributions]).round(1)
    stats[:avg_castle_raze_contribution] = average(stats[:castle_raze_contributions]).round(1)
    stats[:avg_castles_razed] = average(stats[:castles_razed_values]).round(2)
    stats[:avg_heal_contribution] = average(stats[:heal_contributions]).round(1)
    stats[:avg_team_heal_contribution] = average(stats[:team_heal_contributions]).round(1)
    stats[:avg_contribution_rank] = average(stats[:contribution_ranks]).round(2)

    # Finalize faction stats
    stats[:faction_stats].each do |_faction_id, fs|
      fs[:win_rate] = fs[:games] > 0 ? (fs[:wins].to_f / fs[:games] * 100).round(1) : 0
      fs[:avg_hero_kill_contribution] = average(fs[:hero_kill_contributions]).round(1)
      fs[:avg_unit_kill_contribution] = average(fs[:unit_kill_contributions]).round(1)
      fs[:avg_castle_raze_contribution] = average(fs[:castle_raze_contributions]).round(1)
      fs[:avg_castles_razed] = average(fs[:castles_razed_values]).round(2)
      fs[:avg_heal_contribution] = average(fs[:heal_contributions]).round(1)
      fs[:avg_team_heal_contribution] = average(fs[:team_heal_contributions]).round(1)
      fs[:avg_contribution_rank] = average(fs[:contribution_ranks]).round(2)
    end

    stats
  end

  def average(array)
    return 0 if array.empty?
    array.sum / array.size.to_f
  end
end
