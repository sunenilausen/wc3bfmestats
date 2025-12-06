# Predicts match outcome for a lobby using adaptive CR/ML weighting
# New players: rely more on ML score (performance metrics)
# Experienced players: rely more on CR (win/loss track record)
#
# Also factors in faction experience - players who rarely play a faction
# have their score adjusted toward neutral (50) based on experience.
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

  # Faction experience: minimum games to be fully confident
  FACTION_GAMES_FOR_FULL_CONFIDENCE = 10

  # Maximum score penalty for no faction experience (in absolute points)
  # A player with 0 games on a faction loses up to this many points from their score
  # This represents the disadvantage of playing an unfamiliar faction
  MAX_FACTION_PENALTY_POINTS = 5.0

  attr_reader :lobby

  def initialize(lobby)
    @lobby = lobby
    @faction_experience_cache = {}
    preload_faction_experience
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
  def player_score(player, faction = nil)
    return nil unless player

    cr = player.custom_rating || 1300
    ml = player.ml_score || 50
    games = player.custom_rating_games_played || 0

    cr_weight, ml_weight = weights_for_games(games)
    cr_norm = normalize_cr(cr)

    base_score = (cr_norm * cr_weight + ml * ml_weight) / 100.0

    # Apply faction experience adjustment if faction provided
    if faction
      faction_games = faction_experience(player.id, faction.id)
      base_score = apply_faction_confidence(base_score, faction_games)
    end

    {
      score: base_score.round(1),
      cr: cr.round,
      ml: ml.round(1),
      games: games,
      cr_weight: cr_weight,
      ml_weight: ml_weight,
      faction_games: faction ? faction_experience(player.id, faction.id) : nil
    }
  end

  # Get faction experience for a player
  def faction_experience(player_id, faction_id)
    @faction_experience_cache[[ player_id, faction_id ]] || 0
  end

  private

  def preload_faction_experience
    player_ids = lobby.lobby_players.filter_map(&:player_id)
    return if player_ids.empty?

    # Get game counts for each player-faction combination in one query
    counts = Appearance.joins(:match)
      .where(player_id: player_ids, matches: { ignored: false })
      .group(:player_id, :faction_id)
      .count

    counts.each do |(player_id, faction_id), count|
      @faction_experience_cache[[ player_id, faction_id ]] = count
    end
  end

  def compute_team_scores(lobby_players)
    lobby_players.filter_map do |lp|
      if lp.is_new_player? && lp.player_id.nil?
        # New player placeholder: use default values
        new_player_score
      elsif lp.player
        compute_lobby_player_score(lp)
      end
    end
  end

  def compute_lobby_player_score(lp)
    player = lp.player
    cr = player.custom_rating || 1300
    ml = player.ml_score || 50
    games = player.custom_rating_games_played || 0

    cr_weight, ml_weight = weights_for_games(games)
    cr_norm = normalize_cr(cr)

    base_score = (cr_norm * cr_weight + ml * ml_weight) / 100.0

    # Apply faction experience adjustment
    faction_games = faction_experience(player.id, lp.faction_id)
    apply_faction_confidence(base_score, faction_games)
  end

  def apply_faction_confidence(score, faction_games)
    # Calculate confidence: 0 games = 0%, 10 games = ~63%, 20 games = ~86%
    confidence = 1 - Math.exp(-faction_games.to_f / FACTION_GAMES_FOR_FULL_CONFIDENCE)

    # Apply a flat penalty for lack of faction experience
    # At 0 games: lose MAX_FACTION_PENALTY_POINTS (5 points)
    # At 10+ games: almost no penalty
    penalty = (1 - confidence) * MAX_FACTION_PENALTY_POINTS
    score - penalty
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
      [ NEW_PLAYER_CR_WEIGHT, NEW_PLAYER_ML_WEIGHT ]
    else
      [ EXPERIENCED_CR_WEIGHT, EXPERIENCED_ML_WEIGHT ]
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
