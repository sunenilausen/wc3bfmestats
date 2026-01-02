# Calculates and stores performance scores for each player-faction combination
# Performance score is the average of performance scores from all matches with that faction
# Faction score combines faction-specific rating and average contribution rank
class PlayerFactionStatsCalculator
  # Minimum games required to be ranked
  MIN_GAMES_FOR_RANKING = 10

  attr_reader :stats_updated, :errors

  def initialize
    @stats_updated = 0
    @errors = []
  end

  def call
    calculate_all_stats
    update_rankings
    calculate_faction_scores
    update_rankings_by_score
    @stats_updated
  end

  # Recalculate only faction scores and rankings (called after FactionRatingRecalculator)
  # This does NOT delete/recreate stats, only updates scores using existing faction_rating
  def recalculate_scores_only
    calculate_faction_scores
    update_rankings_by_score
  end

  private

  def calculate_all_stats
    # Clear existing stats
    PlayerFactionStat.delete_all

    # Get all appearances with their performance scores (exclude early leaver matches)
    appearances_data = Appearance.joins(:match, :faction, :player)
      .where(matches: { ignored: false, has_early_leaver: false })
      .where.not(performance_score: nil)
      .pluck(:player_id, :faction_id, :performance_score, "matches.good_victory", "factions.good")

    # Group by player and faction
    player_faction_data = Hash.new { |h, k| h[k] = { scores: [], wins: 0, games: 0 } }

    appearances_data.each do |player_id, faction_id, score, good_victory, faction_good|
      key = [ player_id, faction_id ]
      player_faction_data[key][:scores] << score
      player_faction_data[key][:games] += 1

      # Determine if player won
      player_won = (faction_good && good_victory) || (!faction_good && !good_victory)
      player_faction_data[key][:wins] += 1 if player_won
    end

    # Create PlayerFactionStat records
    records_to_insert = []
    now = Time.current

    player_faction_data.each do |(player_id, faction_id), data|
      avg_score = data[:scores].sum / data[:scores].size

      records_to_insert << {
        player_id: player_id,
        faction_id: faction_id,
        games_played: data[:games],
        wins: data[:wins],
        performance_score: avg_score.round(2),
        created_at: now,
        updated_at: now
      }
    end

    # Bulk insert
    PlayerFactionStat.insert_all(records_to_insert) if records_to_insert.any?
    @stats_updated = records_to_insert.size
  end

  def update_rankings
    # Rankings are now updated after faction_score is calculated
    # See update_rankings_by_score method
  end

  def update_rankings_by_score
    # Update rankings per faction by faction_score (only for players with MIN_GAMES_FOR_RANKING games)
    Faction.find_each do |faction|
      stats = PlayerFactionStat
        .where(faction: faction)
        .where("games_played >= ?", MIN_GAMES_FOR_RANKING)
        .where.not(faction_score: nil)
        .order(faction_score: :desc)

      stats.each_with_index do |stat, index|
        stat.update_column(:rank, index + 1)
      end
    end
  end

  def calculate_faction_scores
    # Calculate faction-specific scores using the same method as ml_score
    # Based on contribution percentages with caps

    # Batch query all contribution data for efficiency
    calculate_faction_scores_batch
  end

  def calculate_faction_scores_batch
    weights = MlScoreRecalculator::WEIGHTS

    # Get all appearances grouped by player_id and faction_id (exclude early leaver matches)
    appearances_data = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false, has_early_leaver: false })
      .pluck(:player_id, :faction_id, :match_id, :hero_kills, :unit_kills, :castles_razed, :team_heal,
             :ignore_hero_kills, :ignore_unit_kills, "factions.good")

    # Get team totals per match per team
    match_ids = Match.where(ignored: false, has_early_leaver: false).pluck(:id)

    hero_kill_totals = Appearance.joins(:faction)
      .where(match_id: match_ids)
      .where.not(hero_kills: nil)
      .where(ignore_hero_kills: [ false, nil ])
      .group(:match_id, "factions.good")
      .sum(:hero_kills)

    unit_kill_totals = Appearance.joins(:faction)
      .where(match_id: match_ids)
      .where.not(unit_kills: nil)
      .where(ignore_unit_kills: [ false, nil ])
      .group(:match_id, "factions.good")
      .sum(:unit_kills)

    castle_totals = Appearance.joins(:faction)
      .where(match_id: match_ids)
      .where.not(castles_razed: nil)
      .group(:match_id, "factions.good")
      .sum(:castles_razed)

    team_heal_totals = Appearance.joins(:faction)
      .where(match_id: match_ids)
      .where.not(team_heal: nil)
      .where("team_heal > 0")
      .group(:match_id, "factions.good")
      .sum(:team_heal)

    # Calculate contributions per player-faction
    player_faction_contribs = Hash.new { |h, k| h[k] = { hk: [], uk: [], cr: [], th: [] } }

    appearances_data.each do |player_id, faction_id, match_id, hk, uk, cr, th, ignore_hk, ignore_uk, is_good|
      key = [ player_id, faction_id ]

      # Hero kills (capped at 10% per kill)
      if hk && !ignore_hk
        team_total = hero_kill_totals[[ match_id, is_good ]] || 0
        if team_total > 0
          raw_contrib = (hk.to_f / team_total * 100)
          max_contrib = hk * MlScoreRecalculator::HERO_KILL_CAP_PER_KILL
          player_faction_contribs[key][:hk] << [ raw_contrib, max_contrib ].min
        end
      end

      # Unit kills (no cap)
      if uk && !ignore_uk
        team_total = unit_kill_totals[[ match_id, is_good ]] || 0
        if team_total > 0
          player_faction_contribs[key][:uk] << (uk.to_f / team_total * 100)
        end
      end

      # Castle raze (capped at 20% per castle)
      if cr
        team_total = castle_totals[[ match_id, is_good ]] || 0
        if team_total > 0
          raw_contrib = (cr.to_f / team_total * 100)
          max_contrib = cr * MlScoreRecalculator::CASTLE_RAZE_CAP_PER_KILL
          player_faction_contribs[key][:cr] << [ raw_contrib, max_contrib ].min
        end
      end

      # Team heal (capped at 40%)
      if th && th > 0
        team_total = team_heal_totals[[ match_id, is_good ]] || 0
        if team_total > 0
          raw_contrib = (th.to_f / team_total * 100)
          player_faction_contribs[key][:th] << [ raw_contrib, MlScoreRecalculator::TEAM_HEAL_CAP_PER_GAME ].min
        end
      end
    end

    # First pass: calculate raw faction scores
    faction_raw_scores = {}
    PlayerFactionStat.where("games_played >= ?", MIN_GAMES_FOR_RANKING).find_each do |stat|
      key = [ stat.player_id, stat.faction_id ]
      contribs = player_faction_contribs[key]

      next unless contribs

      avg_hk = contribs[:hk].any? ? (contribs[:hk].sum / contribs[:hk].size) : 20.0
      avg_uk = contribs[:uk].any? ? (contribs[:uk].sum / contribs[:uk].size) : 20.0
      avg_cr = contribs[:cr].any? ? (contribs[:cr].sum / contribs[:cr].size) : 20.0
      avg_th = contribs[:th].any? ? (contribs[:th].sum / contribs[:th].size) : 20.0

      # Calculate raw score using same weights as MlScoreRecalculator
      raw_score = 0.0
      raw_score += weights[:hero_kill_contribution] * (avg_hk - 20.0)
      raw_score += weights[:unit_kill_contribution] * (avg_uk - 20.0)
      raw_score += weights[:castle_raze_contribution] * (avg_cr - 20.0)
      raw_score += weights[:team_heal_contribution] * (avg_th - 20.0)

      # Convert to 0-100 scale using sigmoid, then center on 0
      sigmoid_value = 1.0 / (1.0 + Math.exp(-raw_score.clamp(-500, 500) * 0.5))
      centered_score = (sigmoid_value * 100) - 50.0

      faction_raw_scores[stat.id] = centered_score
    end

    # Normalize so average = 0 (positive = above average, negative = below average)
    if faction_raw_scores.any?
      current_avg = faction_raw_scores.values.sum / faction_raw_scores.size

      faction_raw_scores.each do |stat_id, centered_score|
        normalized_score = (centered_score - current_avg).round(1)
        PlayerFactionStat.where(id: stat_id).update_all(faction_score: normalized_score)
      end
    end
  end
end
