# Predicts match outcome for a lobby using CR with ML score adjustment for new players
#
# For experienced players (30+ games): uses CR directly
# For new players (< 30 games): applies penalty if ML score < 50
#   - ML score >= 50 = no adjustment (trust their CR)
#   - ML score < 50 = penalty scales with how far below 50 and scales down as games increase
#
class LobbyWinPredictor
  # Games threshold for full CR trust (no ML adjustment after this)
  GAMES_FOR_FULL_CR_TRUST = 30

  # Maximum CR adjustment based on ML score for brand new players
  MAX_ML_CR_ADJUSTMENT = 200

  # ML score baseline (50 = average, no adjustment)
  ML_BASELINE = 50

  # CR normalization: convert to 0-100 scale (1200 = 0, 1800 = 100)
  CR_MIN = 1200
  CR_MAX = 1800

  attr_reader :lobby

  def initialize(lobby)
    @lobby = lobby
  end

  def predict
    good_players = lobby.lobby_players.select { |lp| lp.faction&.good? }
    evil_players = lobby.lobby_players.reject { |lp| lp.faction&.good? }

    good_crs = compute_team_effective_crs(good_players)
    evil_crs = compute_team_effective_crs(evil_players)

    return nil if good_crs.empty? || evil_crs.empty?

    good_avg = good_crs.sum / good_crs.size
    evil_avg = evil_crs.sum / evil_crs.size

    # Convert CR difference to win probability
    # 100 CR difference ≈ 64% win chance for higher rated team
    cr_diff = good_avg - evil_avg
    good_win_prob = 1.0 / (1 + Math.exp(-cr_diff / 150.0))

    {
      good_win_pct: (good_win_prob * 100).round(1),
      evil_win_pct: ((1 - good_win_prob) * 100).round(1),
      good_avg_cr: good_avg.round,
      evil_avg_cr: evil_avg.round,
      good_details: compute_team_details(good_players),
      evil_details: compute_team_details(evil_players)
    }
  end

  # Compute individual player effective CR for display
  def player_score(player, faction = nil)
    return nil unless player

    cr = player.custom_rating || 1300
    games = player.custom_rating_games_played || 0
    ml_score = player.ml_score || ML_BASELINE

    effective_cr = calculate_effective_cr(cr, games, ml_score)
    ml_adjustment = effective_cr - cr

    {
      effective_cr: effective_cr.round,
      cr: cr.round,
      ml_score: ml_score,
      ml_adjustment: ml_adjustment.round,
      games: games
    }
  end

  private

  def compute_team_effective_crs(lobby_players)
    lobby_players.filter_map do |lp|
      if lp.is_new_player? && lp.player_id.nil?
        # New player placeholder: use default values with penalty
        calculate_effective_cr(
          NewPlayerDefaults.custom_rating,
          0,
          NewPlayerDefaults.ml_score
        )
      elsif lp.player
        calculate_effective_cr(
          lp.player.custom_rating || 1300,
          lp.player.custom_rating_games_played || 0,
          lp.player.ml_score || ML_BASELINE
        )
      end
    end
  end

  # Calculate effective CR with ML score adjustment for new players
  # Only applies penalty for new players with ML score < 50
  # No bonus for any new player - trust their CR if they perform well
  def calculate_effective_cr(cr, games, ml_score)
    return cr.to_f if games >= GAMES_FOR_FULL_CR_TRUST

    # Only apply penalty if ML score is below baseline (50)
    # No bonus for new players above 50
    return cr.to_f if ml_score >= ML_BASELINE

    # ML score deviation from baseline (negative only at this point)
    ml_deviation = ml_score - ML_BASELINE

    # Penalty scales down as games increase
    adjustment_factor = 1.0 - (games.to_f / GAMES_FOR_FULL_CR_TRUST)

    # Scale deviation to CR adjustment (max -200 for ML score 0)
    ml_cr_adjustment = (ml_deviation / 50.0) * MAX_ML_CR_ADJUSTMENT * adjustment_factor

    cr + ml_cr_adjustment
  end

  def compute_team_details(lobby_players)
    players_with_data = lobby_players.select { |lp| lp.player || lp.is_new_player? }

    crs = []
    effective_crs = []
    ml_scores = []
    games_list = []

    players_with_data.each do |lp|
      if lp.is_new_player? && lp.player_id.nil?
        cr = NewPlayerDefaults.custom_rating
        ml = NewPlayerDefaults.ml_score
        crs << cr
        effective_crs << calculate_effective_cr(cr, 0, ml)
        ml_scores << ml
        games_list << 0
      elsif lp.player
        cr = lp.player.custom_rating || 1300
        ml = lp.player.ml_score || ML_BASELINE
        games = lp.player.custom_rating_games_played || 0
        crs << cr
        effective_crs << calculate_effective_cr(cr, games, ml)
        ml_scores << ml
        games_list << games
      end
    end

    return {} if crs.empty?

    {
      avg_cr: (crs.sum / crs.size).round,
      avg_effective_cr: (effective_crs.sum / effective_crs.size).round,
      avg_ml_score: (ml_scores.sum / ml_scores.size).round,
      avg_games: (games_list.sum / games_list.size).round,
      player_count: crs.size
    }
  end
end
