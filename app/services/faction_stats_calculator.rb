# Computes all faction statistics efficiently in minimal passes
class FactionStatsCalculator
  # Factions that get a 1.33x unit kill multiplier for MVP calculation (support factions)
  MVP_UNIT_KILL_BOOST_FACTIONS = [ "Minas Morgul", "Fellowship" ].freeze
  MVP_UNIT_KILL_BOOST = 1.5

  attr_reader :faction, :map_version, :map_versions, :limit

  def initialize(faction, map_version: nil, map_versions: nil, limit: nil)
    @faction = faction
    @map_version = map_version
    @map_versions = map_versions
    @limit = limit
  end

  def compute
    appearances = faction.appearances
      .joins(:match)
      .where(matches: { ignored: false })
      .includes(:player, :faction, match: [ :wc3stats_replay, { appearances: :faction } ])

    if map_version.present?
      appearances = appearances.where(matches: { map_version: map_version })
    elsif map_versions.present?
      appearances = appearances.where(matches: { map_version: map_versions })
    end

    # Apply limit if specified (most recent games first)
    if limit.present? && limit > 0
      appearances = appearances.merge(Match.reverse_chronological).limit(limit)
    end

    stats = {
      avg_unit_kills: 0,
      avg_hero_kills: 0,
      avg_unit_kills_per_min: 0,
      avg_hero_kills_per_min: 0,
      avg_hero_kill_contribution: 0,
      avg_unit_kill_contribution: 0,
      avg_castles_razed: 0,
      times_top_hero_kills: 0,
      times_top_unit_kills: 0,
      times_mvp: 0,
      total_games: 0,
      total_wins: 0,
      top_winrate_players: [],
      most_wins_players: [],
      top_hero_killers: [],
      top_unit_killers: []
    }

    return stats if appearances.empty?

    # Collect data in single pass
    player_stats = Hash.new { |h, k| h[k] = { player: nil, wins: 0, games: 0, top_hero: 0.0, top_unit: 0.0 } }
    hero_contributions = []
    unit_contributions = []
    castle_raze_contributions = []
    castles_razed_values = []
    heal_contributions = []
    team_heal_contributions = []
    contribution_ranks = []
    total_unit_kills = 0
    total_hero_kills = 0
    total_minutes = 0.0
    times_top_hero = 0.0
    times_top_unit = 0.0
    times_mvp = 0
    total_wins = 0

    appearances.each do |appearance|
      match = appearance.match
      player = appearance.player
      player_good = faction.good?

      # Track player
      ps = player_stats[player.id]
      ps[:player] = player
      ps[:games] += 1

      # Win check
      player_won = (player_good && match.good_victory?) || (!player_good && !match.good_victory?)
      if player_won
        ps[:wins] += 1
        total_wins += 1
      end

      # Get team appearances
      team_appearances = match.appearances.select { |a| a.faction.good? == player_good }

      # Hero kill stats - use stored percentage if available
      if appearance.hero_kill_pct
        total_hero_kills += appearance.hero_kills
        hero_contributions << appearance.hero_kill_pct
      elsif !appearance.hero_kills.nil? && !appearance.ignore_hero_kills?
        # Fallback: calculate if not stored (no cap - raw percentage for display)
        total_hero_kills += appearance.hero_kills
        team_with_hero = team_appearances.select { |a| !a.hero_kills.nil? && !a.ignore_hero_kills? }
        if team_with_hero.any?
          team_total = team_with_hero.sum(&:hero_kills)
          if team_total > 0
            hero_contributions << (appearance.hero_kills.to_f / team_total * 100)
          end
        end
      end

      # Top hero kills - use stored flag if available, otherwise calculate with tie-sharing
      if appearance.top_hero_kills?
        team_with_hero = team_appearances.select { |a| !a.hero_kills.nil? && !a.ignore_hero_kills? }
        if team_with_hero.any?
          tied_count = team_with_hero.count { |a| a.top_hero_kills? }
          tied_count = 1 if tied_count == 0 # Fallback if flags not yet populated
          share = 1.0 / tied_count
          times_top_hero += share
          ps[:top_hero] += share
        else
          times_top_hero += 1
          ps[:top_hero] += 1
        end
      elsif !appearance.hero_kills.nil? && !appearance.ignore_hero_kills? && appearance.top_hero_kills.nil?
        # Fallback: calculate if flag not stored (for backwards compatibility)
        team_with_hero = team_appearances.select { |a| !a.hero_kills.nil? && !a.ignore_hero_kills? }
        if team_with_hero.any?
          max_hero = team_with_hero.map(&:hero_kills).max
          if appearance.hero_kills == max_hero && max_hero > 0
            tied_count = team_with_hero.count { |a| a.hero_kills == max_hero }
            share = 1.0 / tied_count
            times_top_hero += share
            ps[:top_hero] += share
          end
        end
      end

      # Unit kill stats - use stored percentage if available
      if appearance.unit_kill_pct
        total_unit_kills += appearance.unit_kills
        unit_contributions << appearance.unit_kill_pct
      elsif appearance.unit_kills.present? && !appearance.ignore_unit_kills?
        # Fallback: calculate if not stored
        total_unit_kills += appearance.unit_kills
        team_with_unit = team_appearances.select { |a| a.unit_kills.present? && !a.ignore_unit_kills? }
        if team_with_unit.any?
          team_total = team_with_unit.sum(&:unit_kills)
          if team_total > 0
            unit_contributions << (appearance.unit_kills.to_f / team_total * 100)
          end
        end
      end

      # Top unit kills - use stored flag if available, otherwise calculate with tie-sharing
      if appearance.top_unit_kills?
        team_with_unit = team_appearances.select { |a| a.unit_kills.present? && !a.ignore_unit_kills? }
        if team_with_unit.any?
          tied_count = team_with_unit.count { |a| a.top_unit_kills? }
          tied_count = 1 if tied_count == 0 # Fallback if flags not yet populated
          share = 1.0 / tied_count
          times_top_unit += share
          ps[:top_unit] += share
        else
          times_top_unit += 1
          ps[:top_unit] += 1
        end
      elsif appearance.unit_kills.present? && !appearance.ignore_unit_kills? && appearance.top_unit_kills.nil?
        # Fallback: calculate if flag not stored (for backwards compatibility)
        team_with_unit = team_appearances.select { |a| a.unit_kills.present? && !a.ignore_unit_kills? }
        if team_with_unit.any?
          max_unit = team_with_unit.map(&:unit_kills).max
          if appearance.unit_kills == max_unit
            tied_count = team_with_unit.count { |a| a.unit_kills == max_unit }
            share = 1.0 / tied_count
            times_top_unit += share
            ps[:top_unit] += share
          end
        end
      end

      # MVP: use stored is_mvp field (set by CustomRatingRecalculator)
      if appearance.is_mvp?
        times_mvp += 1
      end

      # Contribution rank: use stored value if available
      if appearance.contribution_rank
        contribution_ranks << appearance.contribution_rank
      elsif team_appearances.size >= 2
        # Fallback: calculate if not stored
        ranked = team_appearances.map do |a|
          { appearance: a, score: performance_score(a, team_appearances, match) }
        end.sort_by { |r| -r[:score] }

        rank = ranked.index { |r| r[:appearance].id == appearance.id }
        contribution_ranks << (rank + 1) if rank
      end

      # Duration for per-minute stats
      total_minutes += match.seconds / 60.0 if match.seconds.present?

      # Castles razed contribution - use stored percentage if available
      if appearance.castles_razed.present?
        castles_razed_values << appearance.castles_razed

        if appearance.castle_raze_pct
          castle_raze_contributions << appearance.castle_raze_pct
        else
          team_with_castles = team_appearances.select { |a| a.castles_razed.present? }
          if team_with_castles.any?
            team_total = team_with_castles.sum(&:castles_razed)
            if team_total > 0
              castle_raze_contributions << (appearance.castles_razed.to_f / team_total * 100)
            end
          end
        end
      end

      # Heal contribution - use stored percentage if available
      if appearance.heal_pct
        heal_contributions << appearance.heal_pct
      elsif appearance.total_heal.present? && appearance.total_heal > 0
        team_with_heal = team_appearances.select { |a| a.total_heal.present? && a.total_heal > 0 }
        if team_with_heal.any?
          team_total = team_with_heal.sum(&:total_heal)
          if team_total > 0
            heal_contributions << (appearance.total_heal.to_f / team_total * 100)
          end
        end
      end

      # Team heal contribution - use stored percentage if available
      if appearance.team_heal_pct
        team_heal_contributions << appearance.team_heal_pct
      elsif appearance.team_heal.present? && appearance.team_heal > 0
        team_with_team_heal = team_appearances.select { |a| a.team_heal.present? && a.team_heal > 0 }
        if team_with_team_heal.any?
          team_total = team_with_team_heal.sum(&:team_heal)
          if team_total > 0
            team_heal_contributions << (appearance.team_heal.to_f / team_total * 100)
          end
        end
      end
    end

    total_games = appearances.size
    stats[:total_games] = total_games
    stats[:unique_players] = player_stats.size

    # Averages
    stats[:avg_unit_kills] = (total_unit_kills.to_f / total_games).round(1)
    stats[:avg_hero_kills] = (total_hero_kills.to_f / total_games).round(1)
    stats[:avg_unit_kills_per_min] = total_minutes > 0 ? (total_unit_kills / total_minutes).round(2) : 0
    stats[:avg_hero_kills_per_min] = total_minutes > 0 ? (total_hero_kills / total_minutes).round(2) : 0

    # Contribution stats
    stats[:avg_hero_kill_contribution] = hero_contributions.any? ? (hero_contributions.sum / hero_contributions.size).round(1) : 0
    stats[:avg_unit_kill_contribution] = unit_contributions.any? ? (unit_contributions.sum / unit_contributions.size).round(1) : 0
    stats[:avg_castle_raze_contribution] = castle_raze_contributions.any? ? (castle_raze_contributions.sum / castle_raze_contributions.size).round(1) : 0
    stats[:avg_castles_razed] = castles_razed_values.any? ? (castles_razed_values.sum.to_f / castles_razed_values.size).round(2) : 0
    stats[:avg_heal_contribution] = heal_contributions.any? ? (heal_contributions.sum / heal_contributions.size).round(1) : 0
    stats[:avg_team_heal_contribution] = team_heal_contributions.any? ? (team_heal_contributions.sum / team_heal_contributions.size).round(1) : 0
    stats[:avg_contribution_rank] = contribution_ranks.any? ? (contribution_ranks.sum.to_f / contribution_ranks.size).round(2) : 0
    stats[:times_top_hero_kills] = times_top_hero
    stats[:times_top_unit_kills] = times_top_unit
    stats[:top_hero_kills_pct] = total_games > 0 ? (times_top_hero.to_f / total_games * 100).round(1) : 0
    stats[:top_unit_kills_pct] = total_games > 0 ? (times_top_unit.to_f / total_games * 100).round(1) : 0
    stats[:times_mvp] = times_mvp
    stats[:total_wins] = total_wins
    stats[:mvp_pct] = total_wins > 0 ? (times_mvp.to_f / total_wins * 100).round(1) : 0

    # Player leaderboards
    player_data = player_stats.values

    # Top winrate (min 10 games)
    stats[:top_winrate_players] = player_data
      .select { |p| p[:games] >= 10 }
      .map { |p| p.merge(winrate: (p[:wins].to_f / p[:games] * 100).round(1)) }
      .sort_by { |p| -p[:winrate] }
      .first(5)

    # Most wins
    stats[:most_wins_players] = player_data
      .sort_by { |p| -p[:wins] }
      .first(5)

    # Top hero killers (by times top on team, min 5 games)
    stats[:top_hero_killers] = player_data
      .select { |p| p[:games] >= 5 }
      .map { |p| p.merge(top_pct: (p[:top_hero].to_f / p[:games] * 100).round(1)) }
      .sort_by { |p| -p[:top_pct] }
      .first(5)

    # Top unit killers (by times top on team, min 5 games)
    stats[:top_unit_killers] = player_data
      .select { |p| p[:games] >= 5 }
      .map { |p| p.merge(top_pct: (p[:top_unit].to_f / p[:games] * 100).round(1)) }
      .sort_by { |p| -p[:top_pct] }
      .first(5)

    stats
  end

  private

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
        hk_contrib = [ raw_contrib, max_contrib_by_kills, 40.0 ].min
        score += (hk_contrib - 20.0) * weights[:hero_kill_contribution]
      end
    end

    # Unit kill contribution (capped at 40%)
    if appearance.unit_kills && !appearance.ignore_unit_kills?
      team_unit_kills = team_appearances.sum { |a| (a.unit_kills && !a.ignore_unit_kills?) ? a.unit_kills : 0 }
      if team_unit_kills > 0
        uk_contrib = [ (appearance.unit_kills.to_f / team_unit_kills) * 100, 40.0 ].min
        score += (uk_contrib - 20.0) * weights[:unit_kill_contribution]
      end
    end

    # Castle raze contribution (capped at 30%)
    if appearance.castles_razed
      team_castles = team_appearances.sum { |a| a.castles_razed || 0 }
      if team_castles > 0
        cr_contrib = [ (appearance.castles_razed.to_f / team_castles) * 100, 30.0 ].min
        score += (cr_contrib - 20.0) * weights[:castle_raze_contribution]
      end
    end

    # Team heal contribution (capped at 40%)
    if appearance.team_heal && appearance.team_heal > 0
      team_heal_total = team_appearances.sum { |a| (a.team_heal && a.team_heal > 0) ? a.team_heal : 0 }
      if team_heal_total > 0
        th_contrib = [ (appearance.team_heal.to_f / team_heal_total) * 100, 40.0 ].min
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
end
