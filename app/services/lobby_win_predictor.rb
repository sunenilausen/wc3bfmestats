# Predicts match outcome for a lobby using adaptive CR/Rank weighting
# Uses average contribution rank (1-5, where 1 is best) as performance metric
#
# Also factors in faction experience - players who rarely play a faction
# have their score adjusted toward neutral (50) based on experience.
#
class LobbyWinPredictor
  # Games thresholds for weighting transitions
  GAMES_THRESHOLD_LOW = 10   # First transition point
  GAMES_THRESHOLD_HIGH = 100 # Second transition point (rank weight reaches minimum)

  # Weights for brand new players (0 games) - both CR and rank unreliable, use neutral
  NEW_PLAYER_CR_WEIGHT = 50
  NEW_PLAYER_RANK_WEIGHT = 50

  # Weights at 10 games
  MID_CR_WEIGHT = 60
  MID_RANK_WEIGHT = 40

  # Weights for very experienced players (100+ games) - CR is very reliable, rank is secondary
  EXPERIENCED_CR_WEIGHT = 80
  EXPERIENCED_RANK_WEIGHT = 20

  # CR normalization: convert to 0-100 scale (1200 = 0, 1800 = 100)
  CR_MIN = 1200
  CR_MAX = 1800

  # Faction experience: minimum games to be fully confident
  FACTION_GAMES_FOR_FULL_CONFIDENCE = 10

  # Faction rank fully kicks in after this many games with faction
  FACTION_GAMES_FOR_FACTION_RANK = 20

  # Default rank for players with no faction experience
  DEFAULT_FACTION_RANK = 4.5

  # Maximum score penalty for no faction experience (in absolute points)
  # A player with 0 games on a faction loses up to this many points from their score
  # This represents the disadvantage of playing an unfamiliar faction
  MAX_FACTION_PENALTY_POINTS = 5.0

  attr_reader :lobby

  def initialize(lobby)
    @lobby = lobby
    @faction_experience_cache = {}
    @avg_rank_cache = {}
    @faction_rank_cache = {}
    preload_faction_experience
    preload_avg_ranks
    preload_faction_ranks
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
    games = player.custom_rating_games_played || 0

    # Calculate blended rank: 50% overall avg rank + 50% faction rank component
    # Faction rank component transitions from 4.5 (0 games) to actual faction avg (20+ games)
    overall_avg_rank = @avg_rank_cache[player.id] || 4.0

    faction_rank_component = DEFAULT_FACTION_RANK
    if faction
      faction_data = @faction_rank_cache[[ player.id, faction.id ]]
      faction_rank_component = if faction_data && faction_data[:count] >= FACTION_GAMES_FOR_FACTION_RANK
        # 20+ games: use actual faction avg
        faction_data[:avg]
      elsif faction_data && faction_data[:count] > 0
        # 1-19 games: gradual transition from 4.5 to faction avg
        progress = faction_data[:count].to_f / FACTION_GAMES_FOR_FACTION_RANK
        DEFAULT_FACTION_RANK + (faction_data[:avg] - DEFAULT_FACTION_RANK) * progress
      else
        # 0 games: use default 4.5
        DEFAULT_FACTION_RANK
      end
    end

    # Blend: 50% overall + 50% faction component
    avg_rank = (overall_avg_rank * 0.5) + (faction_rank_component * 0.5)
    rank_score = rank_to_score(avg_rank)

    cr_weight, rank_weight = weights_for_games(games)
    cr_norm = normalize_cr(cr)

    base_score = (cr_norm * cr_weight + rank_score * rank_weight) / 100.0

    # Apply faction experience adjustment if faction provided
    if faction
      faction_games = faction_experience(player.id, faction.id)
      base_score = apply_faction_confidence(base_score, faction_games)
    end

    {
      score: base_score.round(1),
      cr: cr.round,
      avg_rank: avg_rank.round(2),
      rank_score: rank_score.round(1),
      games: games,
      cr_weight: cr_weight,
      rank_weight: rank_weight,
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

  def preload_avg_ranks
    player_ids = lobby.lobby_players.filter_map(&:player_id)
    return if player_ids.empty?

    # Get average contribution rank per player (only from non-ignored matches with rank data)
    avg_ranks = Appearance.joins(:match)
      .where(player_id: player_ids, matches: { ignored: false })
      .where.not(contribution_rank: nil)
      .group(:player_id)
      .average(:contribution_rank)

    avg_ranks.each do |player_id, avg_rank|
      @avg_rank_cache[player_id] = avg_rank.to_f
    end
  end

  def preload_faction_ranks
    player_ids = lobby.lobby_players.filter_map(&:player_id)
    return if player_ids.empty?

    # Get average contribution rank and game count per player-faction combination
    faction_data = Appearance.joins(:match)
      .where(player_id: player_ids, matches: { ignored: false })
      .where.not(contribution_rank: nil)
      .group(:player_id, :faction_id)
      .pluck(:player_id, :faction_id, Arel.sql("AVG(contribution_rank)"), Arel.sql("COUNT(*)"))

    faction_data.each do |player_id, faction_id, avg_rank, count|
      @faction_rank_cache[[ player_id, faction_id ]] = { avg: avg_rank.to_f, count: count }
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
    games = player.custom_rating_games_played || 0

    # Calculate blended rank: 50% overall avg rank + 50% faction rank component
    # Faction rank component transitions from 4.5 (0 games) to actual faction avg (20+ games)
    overall_avg_rank = @avg_rank_cache[player.id] || 4.0

    faction_data = @faction_rank_cache[[ player.id, lp.faction_id ]]
    faction_rank_component = if faction_data && faction_data[:count] >= FACTION_GAMES_FOR_FACTION_RANK
      # 20+ games: use actual faction avg
      faction_data[:avg]
    elsif faction_data && faction_data[:count] > 0
      # 1-19 games: gradual transition from 4.5 to faction avg
      progress = faction_data[:count].to_f / FACTION_GAMES_FOR_FACTION_RANK
      DEFAULT_FACTION_RANK + (faction_data[:avg] - DEFAULT_FACTION_RANK) * progress
    else
      # 0 games: use default 4.5
      DEFAULT_FACTION_RANK
    end

    # Blend: 50% overall + 50% faction component
    avg_rank = (overall_avg_rank * 0.5) + (faction_rank_component * 0.5)
    rank_score = rank_to_score(avg_rank)

    cr_weight, rank_weight = weights_for_games(games)
    cr_norm = normalize_cr(cr)

    base_score = (cr_norm * cr_weight + rank_score * rank_weight) / 100.0

    # Apply faction experience adjustment
    faction_games = faction_experience(player.id, lp.faction_id)
    apply_faction_confidence(base_score, faction_games)
  end

  # Convert contribution rank (1-5) to 0-100 score
  # Rank 1 (best) = 100, Rank 3 (average) = 50, Rank 5 (worst) = 0
  def rank_to_score(rank)
    ((5.0 - rank) / 4.0 * 100).clamp(0, 100)
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
    games = 0

    cr_weight, rank_weight = weights_for_games(games)
    cr_norm = normalize_cr(cr)
    rank_score = rank_to_score(4.0)  # Default to below-average rank for unknown players

    (cr_norm * cr_weight + rank_score * rank_weight) / 100.0
  end

  def weights_for_games(games)
    if games >= GAMES_THRESHOLD_HIGH
      # 100+ games: 80% CR, 20% Rank
      [ EXPERIENCED_CR_WEIGHT, EXPERIENCED_RANK_WEIGHT ]
    elsif games >= GAMES_THRESHOLD_LOW
      # 10-100 games: gradual transition from 60/40 to 80/20
      progress = (games - GAMES_THRESHOLD_LOW).to_f / (GAMES_THRESHOLD_HIGH - GAMES_THRESHOLD_LOW)
      cr_weight = MID_CR_WEIGHT + (EXPERIENCED_CR_WEIGHT - MID_CR_WEIGHT) * progress
      rank_weight = MID_RANK_WEIGHT + (EXPERIENCED_RANK_WEIGHT - MID_RANK_WEIGHT) * progress
      [ cr_weight, rank_weight ]
    else
      # 0-10 games: gradual transition from 50/50 to 60/40
      progress = games.to_f / GAMES_THRESHOLD_LOW
      cr_weight = NEW_PLAYER_CR_WEIGHT + (MID_CR_WEIGHT - NEW_PLAYER_CR_WEIGHT) * progress
      rank_weight = NEW_PLAYER_RANK_WEIGHT + (MID_RANK_WEIGHT - NEW_PLAYER_RANK_WEIGHT) * progress
      [ cr_weight, rank_weight ]
    end
  end

  def normalize_cr(cr)
    # Convert CR to 0-100 scale
    ((cr - CR_MIN) / (CR_MAX - CR_MIN).to_f * 100).clamp(0, 100)
  end

  def compute_team_details(lobby_players)
    players_with_data = lobby_players.select { |lp| lp.player || lp.is_new_player? }

    crs = []
    rank_scores = []
    games_list = []

    players_with_data.each do |lp|
      if lp.is_new_player? && lp.player_id.nil?
        crs << NewPlayerDefaults.custom_rating
        rank_scores << rank_to_score(4.0)  # Default to below-average rank for unknown players
        games_list << 0
      elsif lp.player
        crs << (lp.player.custom_rating || 1300)

        # Calculate blended rank: 50% overall avg rank + 50% faction rank component
        overall_avg_rank = @avg_rank_cache[lp.player.id] || 4.0

        faction_data = @faction_rank_cache[[ lp.player.id, lp.faction_id ]]
        faction_rank_component = if faction_data && faction_data[:count] >= FACTION_GAMES_FOR_FACTION_RANK
          faction_data[:avg]
        elsif faction_data && faction_data[:count] > 0
          progress = faction_data[:count].to_f / FACTION_GAMES_FOR_FACTION_RANK
          DEFAULT_FACTION_RANK + (faction_data[:avg] - DEFAULT_FACTION_RANK) * progress
        else
          DEFAULT_FACTION_RANK
        end

        avg_rank = (overall_avg_rank * 0.5) + (faction_rank_component * 0.5)
        rank_scores << rank_to_score(avg_rank)
        games_list << (lp.player.custom_rating_games_played || 0)
      end
    end

    return {} if crs.empty?

    {
      avg_cr: (crs.sum / crs.size).round,
      avg_rank_score: (rank_scores.sum / rank_scores.size).round(1),
      avg_games: (games_list.sum / games_list.size).round,
      player_count: crs.size
    }
  end
end
