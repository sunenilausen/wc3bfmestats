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
      wins_as_underdog: 0,
      losses_as_underdog: 0,
      wins_as_favorite: 0,
      losses_as_favorite: 0,
      underdog_elo_diffs: [],
      favorite_elo_diffs: [],
      times_top_hero_kills: 0,
      times_top_unit_kills: 0,
      hero_kill_contributions: [],
      unit_kill_contributions: [],
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
      hero_kill_contributions: [],
      unit_kill_contributions: []
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
    else
      stats[:losses] += 1
      stats[:faction_stats][faction_id][:losses] += 1
    end

    # Underdog/favorite calculation
    process_elo_stats(appearance, team_appearances, opponent_appearances, player_won, stats)

    # Kill stats
    process_kill_stats(appearance, team_appearances, player_good, stats, faction_id)
  end

  def process_elo_stats(appearance, team_appearances, opponent_appearances, player_won, stats)
    return unless appearance.elo_rating

    team_with_elo = team_appearances.select { |a| a.elo_rating.present? }
    opponents_with_elo = opponent_appearances.select { |a| a.elo_rating.present? }

    return if team_with_elo.empty? || opponents_with_elo.empty?

    team_avg_elo = team_with_elo.sum(&:elo_rating).to_f / team_with_elo.size
    opponent_avg_elo = opponents_with_elo.sum(&:elo_rating).to_f / opponents_with_elo.size
    elo_diff = (team_avg_elo - opponent_avg_elo).abs
    is_underdog = team_avg_elo < opponent_avg_elo

    if is_underdog
      stats[:underdog_elo_diffs] << elo_diff
      if player_won
        stats[:wins_as_underdog] += 1
      else
        stats[:losses_as_underdog] += 1
      end
    else
      stats[:favorite_elo_diffs] << elo_diff
      if player_won
        stats[:wins_as_favorite] += 1
      else
        stats[:losses_as_favorite] += 1
      end
    end
  end

  def process_kill_stats(appearance, team_appearances, player_good, stats, faction_id)
    faction_stats = stats[:faction_stats][faction_id]

    # Hero kills - skip if flagged to ignore
    if appearance.hero_kills.present? && !appearance.ignore_hero_kills?
      team_with_hero_kills = team_appearances.select { |a| a.hero_kills.present? && !a.ignore_hero_kills? }

      if team_with_hero_kills.any?
        max_hero_kills = team_with_hero_kills.map(&:hero_kills).max
        if appearance.hero_kills == max_hero_kills
          stats[:times_top_hero_kills] += 1
          faction_stats[:times_top_hero_kills] += 1
        end

        team_total = team_with_hero_kills.sum(&:hero_kills)
        if team_total > 0
          contribution = (appearance.hero_kills.to_f / team_total * 100)
          stats[:hero_kill_contributions] << contribution
          faction_stats[:hero_kill_contributions] << contribution
        end
      end
    end

    # Unit kills - skip if flagged to ignore
    if appearance.unit_kills.present? && !appearance.ignore_unit_kills?
      team_with_unit_kills = team_appearances.select { |a| a.unit_kills.present? && !a.ignore_unit_kills? }

      if team_with_unit_kills.any?
        max_unit_kills = team_with_unit_kills.map(&:unit_kills).max
        if appearance.unit_kills == max_unit_kills
          stats[:times_top_unit_kills] += 1
          faction_stats[:times_top_unit_kills] += 1
        end

        team_total = team_with_unit_kills.sum(&:unit_kills)
        if team_total > 0
          contribution = (appearance.unit_kills.to_f / team_total * 100)
          stats[:unit_kill_contributions] << contribution
          faction_stats[:unit_kill_contributions] << contribution
        end
      end
    end
  end

  def finalize_stats(stats)
    # Compute averages
    stats[:avg_underdog_elo_diff] = average(stats[:underdog_elo_diffs]).round(0)
    stats[:avg_favorite_elo_diff] = average(stats[:favorite_elo_diffs]).round(0)
    stats[:avg_hero_kill_contribution] = average(stats[:hero_kill_contributions]).round(1)
    stats[:avg_unit_kill_contribution] = average(stats[:unit_kill_contributions]).round(1)

    # Finalize faction stats
    stats[:faction_stats].each do |_faction_id, fs|
      fs[:win_rate] = fs[:games] > 0 ? (fs[:wins].to_f / fs[:games] * 100).round(1) : 0
      fs[:avg_hero_kill_contribution] = average(fs[:hero_kill_contributions]).round(1)
      fs[:avg_unit_kill_contribution] = average(fs[:unit_kill_contributions]).round(1)
    end

    stats
  end

  def average(array)
    return 0 if array.empty?
    array.sum / array.size.to_f
  end
end
