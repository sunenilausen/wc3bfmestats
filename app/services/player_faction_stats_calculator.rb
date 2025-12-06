# Calculates and stores performance scores for each player-faction combination
# Performance score is the average of performance scores from all matches with that faction
# Faction score is similar to ML score but uses faction-specific rating and stats
class PlayerFactionStatsCalculator
  # Minimum games required to be ranked
  MIN_GAMES_FOR_RANKING = 10

  # Same weights as MlScoreRecalculator
  WEIGHTS = MlScoreRecalculator::WEIGHTS

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

    # Get all appearances with their performance scores
    appearances_data = Appearance.joins(:match, :faction, :player)
      .where(matches: { ignored: false })
      .where.not(performance_score: nil)
      .pluck(:player_id, :faction_id, :performance_score, "matches.good_victory", "factions.good")

    # Group by player and faction
    player_faction_data = Hash.new { |h, k| h[k] = { scores: [], wins: 0, games: 0 } }

    appearances_data.each do |player_id, faction_id, score, good_victory, faction_good|
      key = [player_id, faction_id]
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
    # Calculate faction-specific scores using faction rating and faction-specific contribution averages
    # Similar to ML score calculation

    PlayerFactionStat.where("games_played >= ?", MIN_GAMES_FOR_RANKING).find_each do |stat|
      faction_score = calculate_score_for_stat(stat)
      stat.update_column(:faction_score, faction_score) if faction_score
    end
  end

  def calculate_score_for_stat(stat)
    player_id = stat.player_id
    faction_id = stat.faction_id

    # Get all appearances for this player with this faction
    appearances = Appearance.joins(:match, :faction)
      .where(player_id: player_id, faction_id: faction_id)
      .where(matches: { ignored: false })
      .includes(:match)

    return nil if appearances.empty?

    # Calculate faction-specific contribution averages
    hk_contribs = []
    uk_contribs = []
    cr_contribs = []
    th_contribs = []
    hero_uptimes = []

    appearances.each do |app|
      # Hero kill contribution
      if app.hero_kill_pct && app.hero_kill_pct > 0
        hk_contribs << app.hero_kill_pct
      end

      # Unit kill contribution
      if app.unit_kill_pct && app.unit_kill_pct > 0
        uk_contribs << app.unit_kill_pct
      end

      # Castle raze contribution
      if app.castle_raze_pct && app.castle_raze_pct > 0
        cr_contribs << app.castle_raze_pct
      end

      # Team heal contribution
      if app.team_heal_pct && app.team_heal_pct > 0
        th_contribs << app.team_heal_pct
      end

      # Hero uptime (calculate from heroes_lost/heroes_total if available)
      if app.heroes_lost && app.heroes_total && app.heroes_total > 0
        # Estimate uptime: if 0 heroes lost = 100%, if all lost early = lower
        # Simple approximation: (heroes_survived / total) * 100
        heroes_survived = app.heroes_total - app.heroes_lost
        hero_uptimes << (heroes_survived.to_f / app.heroes_total * 100)
      end
    end

    # Calculate averages (default to 20% for contributions, 80% for uptime)
    avg_hk = hk_contribs.any? ? (hk_contribs.sum / hk_contribs.size) : 20.0
    avg_uk = uk_contribs.any? ? (uk_contribs.sum / uk_contribs.size) : 20.0
    avg_cr = cr_contribs.any? ? (cr_contribs.sum / cr_contribs.size) : 20.0
    avg_th = th_contribs.any? ? (th_contribs.sum / th_contribs.size) : 20.0
    avg_uptime = hero_uptimes.any? ? (hero_uptimes.sum / hero_uptimes.size) : 80.0

    # Use faction rating instead of overall CR (default to 1200)
    faction_rating = stat.faction_rating || 1200

    # Calculate raw score using same formula as ML score
    raw_score = 0.0
    raw_score += WEIGHTS[:elo] * (faction_rating - 1200)  # Base 1200 for faction rating
    raw_score += WEIGHTS[:hero_kill_contribution] * (avg_hk - 20.0)
    raw_score += WEIGHTS[:unit_kill_contribution] * (avg_uk - 20.0)
    raw_score += WEIGHTS[:castle_raze_contribution] * (avg_cr - 20.0)
    raw_score += WEIGHTS[:team_heal_contribution] * (avg_th - 20.0)
    raw_score += WEIGHTS[:hero_uptime] * (avg_uptime - 80.0)

    # Apply sigmoid to get 0-100 scale
    sigmoid_value = 1.0 / (1.0 + Math.exp(-raw_score.clamp(-500, 500) * 0.5))
    raw_faction_score = sigmoid_value * 100

    # Apply confidence adjustment based on games played with this faction
    games = stat.games_played
    confidence = 1.0 - Math.exp(-games / 10.0)
    faction_score = (50.0 + (raw_faction_score - 50.0) * confidence).round(1)

    faction_score
  end
end
