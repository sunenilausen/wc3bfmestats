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
    player_stats = Hash.new { |h, k| h[k] = { player: nil, wins: 0, games: 0, top_hero: 0, top_unit: 0 } }
    hero_contributions = []
    unit_contributions = []
    total_unit_kills = 0
    total_hero_kills = 0
    total_minutes = 0.0
    times_top_hero = 0
    times_top_unit = 0

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
            times_top_hero += 1
            ps[:top_hero] += 1
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
            times_top_unit += 1
            ps[:top_unit] += 1
          end

          team_total = team_with_unit.sum(&:unit_kills)
          if team_total > 0
            unit_contributions << (appearance.unit_kills.to_f / team_total * 100)
          end
        end
      end

      # Duration for per-minute stats
      total_minutes += match.seconds / 60.0 if match.seconds.present?
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
