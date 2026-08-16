# Predicts match outcome for a lobby using CR with ML score adjustment for new players
#
# For experienced players (30+ games): uses CR directly
# For new players (< 30 games): applies penalty if ML score < 0 (below average)
#   - ML score >= 0 = no adjustment (trust their CR)
#   - ML score < 0 = penalty scales with how far below 0 and scales down as games increase
#
# Note: Analysis shows this penalty provides minimal predictive value (~50/50 when it
# changes the prediction), but is kept for conservative estimation.
#
class LobbyWinPredictor
  # Games threshold for full CR trust (no ML adjustment after this)
  GAMES_FOR_FULL_CR_TRUST = 30

  # Maximum CR adjustment based on ML score for brand new players
  MAX_ML_CR_ADJUSTMENT = 200

  # ML score baseline (0 = average, no adjustment) - uses 0-centered scale
  ML_BASELINE = 0

  # CR normalization: convert to 0-100 scale (1200 = 0, 1800 = 100)
  CR_MIN = 1200
  CR_MAX = 1800

  # Faction familiarity: penalty for playing unfamiliar factions
  MAX_FACTION_FAMILIARITY_PENALTY = 80
  MIN_FACTION_GAMES_THRESHOLD = 5

  # Faction impact weights: how much each faction's player CR contributes to team average
  # Higher weight = more impactful faction (carry), lower = less impactful (support)
  # Team sums: Good = 5.00, Evil = 5.00 (balanced)
  FACTION_IMPACT_WEIGHTS = {
    "Mordor" => 1.08,
    "Gondor" => 1.05,
    "Easterlings" => 0.99,
    "Harad" => 0.98,
    "Isengard" => 0.99,
    "Minas Morgul" => 0.96,
    "Fellowship" => 0.96,
    "Dol Amroth" => 0.99
  }.freeze
  DEFAULT_FACTION_WEIGHT = 1.0

  attr_reader :lobby

  def initialize(lobby)
    @lobby = lobby
  end

  # How far outside their usual factions a player is: 0 when the faction is one
  # they play as often as any other, 1 when they have never played it.
  # Drives both the CR penalty and the extra prediction uncertainty.
  def self.unfamiliarity_ratio(total_games, faction_games)
    return 0.0 if total_games.to_i < MIN_FACTION_GAMES_THRESHOLD

    threshold = [ total_games.to_i / 10.0, MIN_FACTION_GAMES_THRESHOLD.to_f ].max
    ratio = [ faction_games.to_i / threshold, 1.0 ].min

    1.0 - Math.sqrt(ratio)
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
    raw_good_pct = (good_win_prob * 100).round(1)

    # Statistically calibrated win chance, plus the band implied by how well we
    # actually know these players' ratings. Display only - the raw percentage
    # above is what defines "balanced" and drives ratings.
    cr_sigma = combined_cr_uncertainty(good_players, evil_players)
    true_good_pct = PredictionCalibrator.calibrate(raw_good_pct)
    low_pct, high_pct = PredictionCalibrator.band(raw_good_pct, cr_sigma)

    {
      good_win_pct: raw_good_pct,
      evil_win_pct: ((1 - good_win_prob) * 100).round(1),
      good_avg_cr: good_avg.round,
      evil_avg_cr: evil_avg.round,
      true_good_win_pct: true_good_pct,
      true_evil_win_pct: (100 - true_good_pct).round(1),
      true_good_low_pct: low_pct,
      true_good_high_pct: high_pct,
      true_margin_pct: low_pct && high_pct ? ((high_pct - low_pct) / 2).round(1) : nil,
      cr_uncertainty: cr_sigma.round,
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

    familiarity_adj = faction_familiarity_adjustment(player, faction)
    effective_cr += familiarity_adj

    {
      effective_cr: effective_cr.round,
      cr: cr.round,
      ml_score: ml_score,
      ml_adjustment: ml_adjustment.round,
      faction_familiarity_adjustment: familiarity_adj.round,
      games: games
    }
  end

  # Where each lobby player's CR is adjusted before it counts toward their
  # team, keyed by lobby_player id. Display only - predict computes its own.
  def player_adjustments
    lobby.lobby_players.each_with_object({}) do |lp, out|
      breakdown = adjustment_for(lp)
      out[lp.id] = breakdown if breakdown
    end
  end

  # The same breakdown for a single slot, nil for an empty one
  def adjustment_for(lobby_player)
    faction_name = lobby_player.faction&.name
    player = lobby_player.player

    if player
      RatingAdjustment.for(
        cr: player.custom_rating || NewPlayerDefaults.custom_rating,
        games: player.custom_rating_games_played.to_i,
        faction_games: lobby_player.faction ? faction_games_played(player, lobby_player.faction) : 0,
        ml_score: player.ml_score || ML_BASELINE,
        faction_name: faction_name
      )
    elsif lobby_player.is_new_player?
      RatingAdjustment.for(
        cr: NewPlayerDefaults.custom_rating,
        games: 0,
        faction_games: 0,
        ml_score: NewPlayerDefaults.ml_score,
        faction_name: faction_name
      )
    end
  end

  private

  def compute_team_effective_crs(lobby_players)
    lobby_players.filter_map do |lp|
      faction_weight = faction_impact_weight(lp.faction)

      effective_cr = if lp.is_new_player? && lp.player_id.nil?
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

      if effective_cr
        effective_cr += faction_familiarity_adjustment(lp.player, lp.faction)
        effective_cr * faction_weight
      end
    end
  end

  # Uncertainty (in CR) of the difference between the two team averages
  def combined_cr_uncertainty(good_players, evil_players)
    RatingUncertainty.combined_sigma(team_cr_uncertainties(good_players), team_cr_uncertainties(evil_players))
  end

  # Per-player CR uncertainty for a team, weighted the same way their CR is
  def team_cr_uncertainties(lobby_players)
    lobby_players.filter_map do |lp|
      next unless lp.player || lp.is_new_player?
      player_cr_uncertainty(lp.player, lp.faction) * faction_impact_weight(lp.faction)
    end
  end

  # How far off a single player's CR could plausibly be
  def player_cr_uncertainty(player, faction)
    return RatingUncertainty.unknown_player_sigma unless player

    RatingUncertainty.player_sigma(
      games: player.custom_rating_games_played.to_i,
      unfamiliarity: unfamiliarity(player, faction),
      inactivity_multiplier: RatingUncertainty.inactivity_multiplier(last_played_at[player.id]),
      streak: player.current_streak
    )
  end

  # Most recent match date per player in the lobby, in one query
  def last_played_at
    @last_played_at ||= begin
      player_ids = lobby.lobby_players.filter_map(&:player_id)

      if player_ids.empty?
        {}
      else
        Appearance.joins(:match)
          .where(player_id: player_ids, matches: { ignored: false })
          .group(:player_id)
          .maximum("matches.played_at")
      end
    end
  end

  # How far outside their usual factions this player is, 0 (their regular
  # faction) to 1 (never played it). Derived from the CR penalty so the penalty
  # and the extra uncertainty always move together.
  def unfamiliarity(player, faction)
    return 0.0 unless faction

    faction_familiarity_adjustment(player, faction).abs / MAX_FACTION_FAMILIARITY_PENALTY
  end

  def faction_impact_weight(faction)
    return DEFAULT_FACTION_WEIGHT unless faction
    FACTION_IMPACT_WEIGHTS[faction.name] || DEFAULT_FACTION_WEIGHT
  end

  # Penalty for playing an unfamiliar faction (fewer games than average)
  # Uses sqrt easing: a few games quickly reduces penalty, full recovery is gradual
  def faction_familiarity_adjustment(player, faction)
    return 0 unless player && faction

    @familiarity_adjustments ||= {}
    key = [ player.id, faction.id ]
    return @familiarity_adjustments[key] if @familiarity_adjustments.key?(key)

    @familiarity_adjustments[key] = compute_faction_familiarity_adjustment(player, faction)
  end

  def compute_faction_familiarity_adjustment(player, faction)
    RatingAdjustment.familiarity_adjustment(
      player.custom_rating_games_played.to_i,
      faction_games_played(player, faction)
    )
  end

  # Games each lobby player has on each faction, in one query. Falls back to a
  # single lookup for anyone outside the lobby (observers).
  def faction_games_played(player, faction)
    @faction_games_played ||= begin
      player_ids = lobby.lobby_players.filter_map(&:player_id)
      PlayerFactionStat.where(player_id: player_ids)
        .pluck(:player_id, :faction_id, :games_played)
        .each_with_object({}) { |(pid, fid, games), out| out[[ pid, fid ]] = games.to_i }
    end

    return @faction_games_played[[ player.id, faction.id ]].to_i if @faction_games_played.key?([ player.id, faction.id ])
    return 0 if lobby.lobby_players.any? { |lp| lp.player_id == player.id }

    player.player_faction_stats.find_by(faction: faction)&.games_played.to_i
  end

  # Calculate effective CR with ML score adjustment for new players
  # Only applies penalty for new players with ML score < 0 (below average)
  # No bonus for any new player - trust their CR if they perform well
  def calculate_effective_cr(cr, games, ml_score)
    RatingAdjustment.effective_cr(cr, games, ml_score)
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
