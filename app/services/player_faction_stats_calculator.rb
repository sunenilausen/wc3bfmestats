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

    # Get all appearances with their performance scores
    appearances_data = Appearance.joins(:match, :faction, :player)
      .where(matches: { ignored: false })
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

    # Get all appearances for this player with this faction that have contribution rank
    appearances = Appearance.joins(:match, :faction)
      .where(player_id: player_id, faction_id: faction_id)
      .where(matches: { ignored: false })
      .where.not(contribution_rank: nil)

    return nil if appearances.empty?

    # Calculate average contribution rank for this faction
    avg_rank = appearances.average(:contribution_rank).to_f

    # Convert rank (1-5) to 0-100 score: rank 1 = 100, rank 3 = 50, rank 5 = 0
    rank_score = ((5.0 - avg_rank) / 4.0 * 100).clamp(0, 100)

    # Use faction rating normalized to 0-100 (1200 = 0, 1800 = 100)
    faction_rating = stat.faction_rating || 1300
    cr_norm = ((faction_rating - 1200) / 600.0 * 100).clamp(0, 100)

    # Combine CR (80%) and Rank (20%) - same as LobbyWinPredictor for experienced players
    raw_faction_score = (cr_norm * 0.8 + rank_score * 0.2)

    # Apply confidence adjustment based on games played with this faction
    games = stat.games_played
    confidence = 1.0 - Math.exp(-games / 10.0)
    faction_score = (50.0 + (raw_faction_score - 50.0) * confidence).round(1)

    faction_score
  end
end
