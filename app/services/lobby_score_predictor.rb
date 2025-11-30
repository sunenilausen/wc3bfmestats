# Predicts match outcome for a lobby using the trained model weights
class LobbyScorePredictor
  attr_reader :lobby, :weights, :good_features, :evil_features, :player_scores

  def initialize(lobby, event_stats: {}, lobby_player_stats: {})
    @lobby = lobby
    @event_stats = event_stats
    @lobby_player_stats = lobby_player_stats
    @weights = PredictionWeight.current.weights_hash
    @player_scores = {}
  end

  def predict
    # Compute individual player scores first
    compute_player_scores

    @good_features = compute_team_features(true)
    @evil_features = compute_team_features(false)

    return nil if @good_features.nil? || @evil_features.nil?

    # Compute feature differences (good - evil)
    feature_diff = subtract_features(@good_features, @evil_features)

    # Apply logistic regression
    z = @weights[:bias]
    feature_diff.each do |key, value|
      weight_key = key.to_sym
      z += (@weights[weight_key] || 0.0) * (value || 0.0)
    end

    good_win_probability = sigmoid(z)

    {
      good_win_pct: (good_win_probability * 100).round(1),
      evil_win_pct: ((1 - good_win_probability) * 100).round(1),
      good_features: @good_features,
      evil_features: @evil_features,
      feature_diff: feature_diff,
      weights_used: @weights,
      player_scores: @player_scores
    }
  end

  # Compute a score for each player based on their stats
  def compute_player_scores
    @lobby.lobby_players.each do |lp|
      # Handle new players (no player_id but marked as new)
      if lp.is_new_player? && lp.player_id.nil?
        @player_scores[:new_player] ||= {
          score: new_player_ml_score,
          raw_score: 0,
          features: new_player_features
        }
        next
      end

      next unless lp.player_id

      player = lp.player
      next unless player

      features = compute_player_features(player)
      next unless features

      # Calculate raw score (weighted sum of features)
      raw_score = compute_raw_score(features)

      # Normalize to a 0-100 scale centered around 50
      # Using sigmoid-like transformation with confidence adjustment
      games_played = features[:games_played] || 0
      normalized_score = normalize_score(raw_score, games_played: games_played)

      @player_scores[player.id] = {
        score: normalized_score,
        raw_score: raw_score.round(2),
        features: features
      }
    end
  end

  # Returns detailed breakdown of how each factor contributes
  def feature_contributions
    return nil unless @good_features && @evil_features

    feature_diff = subtract_features(@good_features, @evil_features)
    contributions = {}

    feature_diff.each do |key, value|
      weight = @weights[key.to_sym] || 0.0
      contribution = weight * (value || 0.0)
      contributions[key] = {
        good_value: @good_features[key]&.round(2),
        evil_value: @evil_features[key]&.round(2),
        difference: value&.round(2),
        weight: weight.round(4),
        contribution: contribution.round(4)
      }
    end

    contributions
  end

  private

  def compute_team_features(is_good)
    # Include both real players and new players marked as is_new_player
    lobby_players = @lobby.lobby_players.select do |lp|
      lp.faction&.good? == is_good && (lp.player_id.present? || lp.is_new_player?)
    end
    return nil if lobby_players.empty?

    features = {
      hero_kd: [],
      hero_kill_contribution: [],
      unit_kill_contribution: [],
      castle_raze_contribution: [],
      games_played: [],
      elo: [],
      enemy_elo_diff: []
    }

    lobby_players.each do |lp|
      # Handle new players with baseline stats
      if lp.is_new_player? && lp.player_id.nil?
        np = new_player_features
        features[:hero_kd] << np[:hero_kd]
        features[:hero_kill_contribution] << np[:hero_kill_contribution]
        features[:unit_kill_contribution] << np[:unit_kill_contribution]
        features[:castle_raze_contribution] << np[:castle_raze_contribution]
        features[:games_played] << np[:games_played]
        features[:elo] << np[:elo]
        features[:enemy_elo_diff] << np[:enemy_elo_diff]
        next
      end

      player = lp.player
      next unless player

      # Get event stats (hero K/D)
      es = @event_stats[player.id]
      if es
        features[:hero_kd] << es[:hero_kd_ratio] if es[:hero_kd_ratio]
      end

      # Get player stats (kill contributions)
      ps = @lobby_player_stats[player.id]
      if ps
        features[:hero_kill_contribution] << ps[:avg_hero_kill_contribution] if ps[:avg_hero_kill_contribution]
        features[:unit_kill_contribution] << ps[:avg_unit_kill_contribution] if ps[:avg_unit_kill_contribution]
        features[:castle_raze_contribution] << ps[:avg_castle_raze_contribution] if ps[:avg_castle_raze_contribution]
        features[:games_played] << ps[:total_matches] if ps[:total_matches]
        features[:enemy_elo_diff] << ps[:avg_enemy_elo_diff] if ps[:avg_enemy_elo_diff]
      end

      # Custom Rating (used as ELO in ML)
      features[:elo] << player.custom_rating if player.custom_rating
    end

    # Average each feature, using defaults for missing data
    {
      hero_kd: safe_average(features[:hero_kd], 1.0),
      hero_kill_contribution: safe_average(features[:hero_kill_contribution], 20.0),
      unit_kill_contribution: safe_average(features[:unit_kill_contribution], 20.0),
      castle_raze_contribution: safe_average(features[:castle_raze_contribution], 20.0),
      games_played: safe_average(features[:games_played], 0),
      elo: safe_average(features[:elo], 1300),
      enemy_elo_diff: safe_average(features[:enemy_elo_diff], 0)
    }
  end

  def subtract_features(good, evil)
    {
      hero_kd: good[:hero_kd] - evil[:hero_kd],
      hero_kill_contribution: good[:hero_kill_contribution] - evil[:hero_kill_contribution],
      unit_kill_contribution: good[:unit_kill_contribution] - evil[:unit_kill_contribution],
      castle_raze_contribution: good[:castle_raze_contribution] - evil[:castle_raze_contribution],
      games_played: good[:games_played] - evil[:games_played],
      elo: good[:elo] - evil[:elo],
      enemy_elo_diff: good[:enemy_elo_diff] - evil[:enemy_elo_diff]
    }
  end

  def safe_average(values, default)
    values = values.compact
    return default if values.empty?
    values.sum.to_f / values.size
  end

  def sigmoid(z)
    1.0 / (1.0 + Math.exp(-z.clamp(-500, 500)))
  end

  def compute_player_features(player)
    features = {}

    # Get event stats (hero K/D)
    es = @event_stats[player.id]
    if es
      features[:hero_kd] = es[:hero_kd_ratio] || 1.0
    else
      features[:hero_kd] = 1.0
    end

    # Get player stats (kill contributions)
    ps = @lobby_player_stats[player.id]
    if ps
      features[:hero_kill_contribution] = ps[:avg_hero_kill_contribution] || 20.0
      features[:unit_kill_contribution] = ps[:avg_unit_kill_contribution] || 20.0
      features[:castle_raze_contribution] = ps[:avg_castle_raze_contribution] || 20.0
      features[:games_played] = ps[:total_matches] || 0
      features[:enemy_elo_diff] = ps[:avg_enemy_elo_diff] || 0
    else
      features[:hero_kill_contribution] = 20.0
      features[:unit_kill_contribution] = 20.0
      features[:castle_raze_contribution] = 20.0
      features[:games_played] = 0
      features[:enemy_elo_diff] = 0
    end

    # Custom Rating (used as ELO in ML)
    features[:elo] = player.custom_rating || 1300

    features
  end

  # Features for a new player (default custom rating, 0 games, baseline stats)
  def new_player_features
    {
      hero_kd: 1.0,
      hero_kill_contribution: 20.0,
      unit_kill_contribution: 20.0,
      castle_raze_contribution: 20.0,
      games_played: 0,
      elo: NewPlayerDefaults.custom_rating,
      enemy_elo_diff: 0
    }
  end

  # ML score for new players: average of bottom 5% of existing players
  def new_player_ml_score
    NewPlayerDefaults.ml_score
  end

  def compute_raw_score(features)
    # Compute weighted sum relative to baseline values
    # Baseline: ELO 1500, Hero K/D 1.0, HK% 20, UK% 20, CR% 20, 0 games, 0 enemy ELO diff
    score = 0.0

    # Custom Rating contribution (relative to 1300)
    score += @weights[:elo] * (features[:elo] - 1300)

    # Hero K/D contribution (relative to 1.0)
    score += @weights[:hero_kd] * (features[:hero_kd] - 1.0)

    # Kill/castle contribution (relative to 20% = equal share of 5 players)
    score += @weights[:hero_kill_contribution] * (features[:hero_kill_contribution] - 20.0)
    score += @weights[:unit_kill_contribution] * (features[:unit_kill_contribution] - 20.0)
    score += @weights[:castle_raze_contribution] * (features[:castle_raze_contribution] - 20.0)

    # Games played contribution
    score += @weights[:games_played] * features[:games_played]

    # Enemy ELO diff contribution (relative to 0 = balanced opponents)
    score += @weights[:enemy_elo_diff] * features[:enemy_elo_diff]

    score
  end

  def normalize_score(raw_score, games_played: 0)
    # Transform raw score to 0-100 scale
    # Using a scaled sigmoid centered at 50
    # Typical raw scores range from about -5 to +5
    raw_ml_score = sigmoid(raw_score * 0.5) * 100

    # Apply confidence adjustment based on games played
    # Players with few games get pulled toward 50 (average)
    # Confidence reaches ~95% at 20 games, ~99% at 50 games
    confidence = 1.0 - Math.exp(-games_played / 10.0)
    (50.0 + (raw_ml_score - 50.0) * confidence).round(1)
  end
end
