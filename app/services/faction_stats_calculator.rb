# Computes all faction statistics efficiently in minimal passes
class FactionStatsCalculator
  attr_reader :faction

  def initialize(faction)
    @faction = faction
  end

  def compute
    appearances = faction.appearances
      .joins(:match)
      .where(matches: { ignored: false })
      .includes(:player, :match, match: { appearances: :faction })

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
      total_games: 0,
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
    total_unit_kills = 0
    total_hero_kills = 0
    total_minutes = 0.0
    times_top_hero = 0.0
    times_top_unit = 0.0

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
      ps[:wins] += 1 if player_won

      # Get team appearances
      team_appearances = match.appearances.select { |a| a.faction.good? == player_good }

      # Hero kill stats - skip if nil or flagged to ignore
      if !appearance.hero_kills.nil? && !appearance.ignore_hero_kills?
        total_hero_kills += appearance.hero_kills

        team_with_hero = team_appearances.select { |a| !a.hero_kills.nil? && !a.ignore_hero_kills? }
        if team_with_hero.any?
          max_hero = team_with_hero.map(&:hero_kills).max
          if appearance.hero_kills == max_hero
            # Share credit when tied - if 2 players tied, each gets 0.5
            tied_count = team_with_hero.count { |a| a.hero_kills == max_hero }
            share = 1.0 / tied_count
            times_top_hero += share
            ps[:top_hero] += share
          end

          team_total = team_with_hero.sum(&:hero_kills)
          if team_total > 0
            hero_contributions << (appearance.hero_kills.to_f / team_total * 100)
          end
        end
      end

      # Unit kill stats - skip if flagged to ignore
      if appearance.unit_kills.present? && !appearance.ignore_unit_kills?
        total_unit_kills += appearance.unit_kills

        team_with_unit = team_appearances.select { |a| a.unit_kills.present? && !a.ignore_unit_kills? }
        if team_with_unit.any?
          max_unit = team_with_unit.map(&:unit_kills).max
          if appearance.unit_kills == max_unit
            # Share credit when tied - if 2 players tied, each gets 0.5
            tied_count = team_with_unit.count { |a| a.unit_kills == max_unit }
            share = 1.0 / tied_count
            times_top_unit += share
            ps[:top_unit] += share
          end

          team_total = team_with_unit.sum(&:unit_kills)
          if team_total > 0
            unit_contributions << (appearance.unit_kills.to_f / team_total * 100)
          end
        end
      end

      # Duration for per-minute stats
      total_minutes += match.seconds / 60.0 if match.seconds.present?

      # Castles razed contribution
      if appearance.castles_razed.present?
        castles_razed_values << appearance.castles_razed

        team_with_castles = team_appearances.select { |a| a.castles_razed.present? }
        if team_with_castles.any?
          team_total = team_with_castles.sum(&:castles_razed)
          if team_total > 0
            castle_raze_contributions << (appearance.castles_razed.to_f / team_total * 100)
          end
        end
      end

      # Heal contribution
      if appearance.total_heal.present? && appearance.total_heal > 0
        team_with_heal = team_appearances.select { |a| a.total_heal.present? && a.total_heal > 0 }
        if team_with_heal.any?
          team_total = team_with_heal.sum(&:total_heal)
          if team_total > 0
            heal_contributions << (appearance.total_heal.to_f / team_total * 100)
          end
        end
      end

      # Team heal contribution
      if appearance.team_heal.present? && appearance.team_heal > 0
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
    stats[:times_top_hero_kills] = times_top_hero
    stats[:times_top_unit_kills] = times_top_unit
    stats[:top_hero_kills_pct] = total_games > 0 ? (times_top_hero.to_f / total_games * 100).round(1) : 0
    stats[:top_unit_kills_pct] = total_games > 0 ? (times_top_unit.to_f / total_games * 100).round(1) : 0

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
end
