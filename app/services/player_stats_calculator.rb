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
      enemy_elo_diffs: [],
      ally_elo_diffs: [],
      times_top_hero_kills: 0,
      times_top_unit_kills: 0,
      hero_kill_contributions: [],
      unit_kill_contributions: [],
      castle_raze_contributions: [],
      castles_razed_values: [],
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
      unit_kill_contributions: [],
      castle_raze_contributions: [],
      castles_razed_values: []
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

    # Castles razed contribution
    process_castle_stats(appearance, team_appearances, stats, faction_id)
  end

  def process_elo_stats(appearance, team_appearances, opponent_appearances, player_won, stats)
    return unless appearance.elo_rating

    team_with_elo = team_appearances.select { |a| a.elo_rating.present? }
    opponents_with_elo = opponent_appearances.select { |a| a.elo_rating.present? }

    return if team_with_elo.empty? || opponents_with_elo.empty?

    player_elo = appearance.elo_rating
    team_avg_elo = team_with_elo.sum(&:elo_rating).to_f / team_with_elo.size
    opponent_avg_elo = opponents_with_elo.sum(&:elo_rating).to_f / opponents_with_elo.size

    # Track player's ELO vs enemy team avg (positive = playing against weaker opponents)
    stats[:enemy_elo_diffs] << (player_elo - opponent_avg_elo)

    # Track player's ELO vs own team avg (positive = carrying weaker teammates)
    # Exclude self from team average for this calculation
    teammates_with_elo = team_with_elo.reject { |a| a.id == appearance.id }
    if teammates_with_elo.any?
      teammates_avg_elo = teammates_with_elo.sum(&:elo_rating).to_f / teammates_with_elo.size
      stats[:ally_elo_diffs] << (player_elo - teammates_avg_elo)
    end

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

    # Hero kills - skip if nil or flagged to ignore
    if !appearance.hero_kills.nil? && !appearance.ignore_hero_kills?
      team_with_hero_kills = team_appearances.select { |a| !a.hero_kills.nil? && !a.ignore_hero_kills? }

      if team_with_hero_kills.any?
        max_hero_kills = team_with_hero_kills.map(&:hero_kills).max
        if appearance.hero_kills == max_hero_kills
          # Share credit when tied - if 2 players tied, each gets 0.5
          tied_count = team_with_hero_kills.count { |a| a.hero_kills == max_hero_kills }
          share = 1.0 / tied_count
          stats[:times_top_hero_kills] += share
          faction_stats[:times_top_hero_kills] += share
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
          # Share credit when tied - if 2 players tied, each gets 0.5
          tied_count = team_with_unit_kills.count { |a| a.unit_kills == max_unit_kills }
          share = 1.0 / tied_count
          stats[:times_top_unit_kills] += share
          faction_stats[:times_top_unit_kills] += share
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

  def process_castle_stats(appearance, team_appearances, stats, faction_id)
    return unless appearance.castles_razed.present?

    faction_stats = stats[:faction_stats][faction_id]
    stats[:castles_razed_values] << appearance.castles_razed
    faction_stats[:castles_razed_values] << appearance.castles_razed

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

    # Finalize faction stats
    stats[:faction_stats].each do |_faction_id, fs|
      fs[:win_rate] = fs[:games] > 0 ? (fs[:wins].to_f / fs[:games] * 100).round(1) : 0
      fs[:avg_hero_kill_contribution] = average(fs[:hero_kill_contributions]).round(1)
      fs[:avg_unit_kill_contribution] = average(fs[:unit_kill_contributions]).round(1)
      fs[:avg_castle_raze_contribution] = average(fs[:castle_raze_contributions]).round(1)
      fs[:avg_castles_razed] = average(fs[:castles_razed_values]).round(2)
    end

    stats
  end

  def average(array)
    return 0 if array.empty?
    array.sum / array.size.to_f
  end
end
