# Predicts match outcome for a lobby using adaptive CR/ML weighting
# New players: rely more on ML score (performance metrics)
# Experienced players: rely more on CR (win/loss track record)
#
# Based on analysis showing:
# - Pure CR: 75% accuracy
# - Pure ML: 64% accuracy
# - Best adaptive: 79% accuracy with threshold-based weighting
#
class LobbyWinPredictor
  # Players with fewer than this many games are considered "new"
  GAMES_THRESHOLD = 10

  # Weights for new players (< GAMES_THRESHOLD games)
  NEW_PLAYER_CR_WEIGHT = 40
  NEW_PLAYER_ML_WEIGHT = 60

  # Weights for experienced players (>= GAMES_THRESHOLD games)
  EXPERIENCED_CR_WEIGHT = 70
  EXPERIENCED_ML_WEIGHT = 30

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

    good_scores = compute_team_scores(good_players)
    evil_scores = compute_team_scores(evil_players)

    return nil if good_scores.empty? || evil_scores.empty?

    good_avg = good_scores.sum / good_scores.size
    evil_avg = evil_scores.sum / evil_scores.size

    # Convert score difference to win probability using logistic function
    # Score difference of ~10 points = ~73% win probability
    score_diff = good_avg - evil_avg
    good_win_prob = 1.0 / (1 + Math.exp(-score_diff / 5.0))

    {
      good_win_pct: (good_win_prob * 100).round(1),
      evil_win_pct: ((1 - good_win_prob) * 100).round(1),
      good_avg_score: good_avg.round(1),
      evil_avg_score: evil_avg.round(1),
      good_details: compute_team_details(good_players),
      evil_details: compute_team_details(evil_players)
    }
  end

  # Compute individual player score for display
  def player_score(player)
    return nil unless player

    cr = player.custom_rating || 1300
    ml = player.ml_score || 50
    games = player.custom_rating_games_played || 0

    cr_weight, ml_weight = weights_for_games(games)
    cr_norm = normalize_cr(cr)

    score = (cr_norm * cr_weight + ml * ml_weight) / 100.0

    {
      score: score.round(1),
      cr: cr.round,
      ml: ml.round(1),
      games: games,
      cr_weight: cr_weight,
      ml_weight: ml_weight
    }
  end

  private

  def compute_team_scores(lobby_players)
    lobby_players.filter_map do |lp|
      if lp.is_new_player? && lp.player_id.nil?
        # New player placeholder: use default values
        new_player_score
      elsif lp.player
        compute_player_score(lp.player)
      end
    end
  end

  def compute_player_score(player)
    cr = player.custom_rating || 1300
    ml = player.ml_score || 50
    games = player.custom_rating_games_played || 0

    cr_weight, ml_weight = weights_for_games(games)
    cr_norm = normalize_cr(cr)

    (cr_norm * cr_weight + ml * ml_weight) / 100.0
  end

  def new_player_score
    cr = NewPlayerDefaults.custom_rating
    ml = NewPlayerDefaults.ml_score
    games = 0

    cr_weight, ml_weight = weights_for_games(games)
    cr_norm = normalize_cr(cr)

    (cr_norm * cr_weight + ml * ml_weight) / 100.0
  end

  def weights_for_games(games)
    if games < GAMES_THRESHOLD
      [NEW_PLAYER_CR_WEIGHT, NEW_PLAYER_ML_WEIGHT]
    else
      [EXPERIENCED_CR_WEIGHT, EXPERIENCED_ML_WEIGHT]
    end
  end

  def normalize_cr(cr)
    # Convert CR to 0-100 scale
    ((cr - CR_MIN) / (CR_MAX - CR_MIN).to_f * 100).clamp(0, 100)
  end

  def compute_team_details(lobby_players)
    players_with_data = lobby_players.select { |lp| lp.player || lp.is_new_player? }

    crs = []
    mls = []
    games_list = []

    players_with_data.each do |lp|
      if lp.is_new_player? && lp.player_id.nil?
        crs << NewPlayerDefaults.custom_rating
        mls << NewPlayerDefaults.ml_score
        games_list << 0
      elsif lp.player
        crs << (lp.player.custom_rating || 1300)
        mls << (lp.player.ml_score || 50)
        games_list << (lp.player.custom_rating_games_played || 0)
      end
    end

    return {} if crs.empty?

    {
      avg_cr: (crs.sum / crs.size).round,
      avg_ml: (mls.sum / mls.size).round(1),
      avg_games: (games_list.sum / games_list.size).round,
      player_count: crs.size
    }
  end
end
