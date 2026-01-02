# Glicko-2 Rating System Recalculator
# Based on Mark Glickman's Glicko-2 algorithm: http://www.glicko.net/glicko/glicko2.pdf
#
# Key concepts:
# - Rating (r): Skill estimate, default 1500
# - Rating Deviation (RD): Uncertainty in rating, default 350 (lower = more reliable)
# - Volatility (σ): Expected fluctuation in rating, default 0.06
#
# Team handling: Uses average opponent team rating/RD for expected score calculation
class Glicko2Recalculator
  # Glicko-2 constants
  DEFAULT_RATING = 1500.0
  DEFAULT_RD = 350.0
  DEFAULT_VOLATILITY = 0.06
  TAU = 0.5  # System constant, constrains volatility change (0.3-1.2 typical)

  # Glicko-2 scaling factor (converts between Glicko and Glicko-2 scale)
  SCALE = 173.7178

  attr_reader :matches_processed, :errors

  def initialize
    @matches_processed = 0
    @errors = []
  end

  def call
    reset_all_ratings
    recalculate_all_matches
    self
  end

  private

  def reset_all_ratings
    Player.update_all(
      glicko2_rating: DEFAULT_RATING,
      glicko2_rating_deviation: DEFAULT_RD,
      glicko2_volatility: DEFAULT_VOLATILITY
    )
  end

  def recalculate_all_matches
    matches = Match.includes(appearances: [ :player, :faction ])
                   .where(ignored: false)
                   .chronological

    matches.each do |match|
      calculate_and_update_ratings(match)
      @matches_processed += 1
    rescue StandardError => e
      @errors << "Match ##{match.id}: #{e.message}"
    end
  end

  def calculate_and_update_ratings(match)
    return if match.appearances.empty?

    good_appearances = match.appearances.select { |a| a.faction.good? }
    evil_appearances = match.appearances.select { |a| !a.faction.good? }

    return if good_appearances.empty? || evil_appearances.empty?

    # For draws, store current ratings with zero change (no rating updates)
    if match.is_draw?
      match.appearances.each do |appearance|
        player = appearance.player
        next unless player

        appearance.glicko2_rating = player.glicko2_rating
        appearance.glicko2_rating_deviation = player.glicko2_rating_deviation
        appearance.glicko2_rating_change = 0
        appearance.save!
      end
      return
    end

    # For early leaver matches, special handling:
    # - Early leaver gets 0 rating change
    # - All other players get 30% reduced rating change
    if match.has_early_leaver?
      store_early_leaver_appearances(match, good_appearances, evil_appearances)
      return
    end

    # Calculate team averages (in Glicko-2 scale)
    good_avg_mu = to_glicko2_scale(average_rating(good_appearances))
    good_avg_phi = to_glicko2_rd(average_rd(good_appearances))
    evil_avg_mu = to_glicko2_scale(average_rating(evil_appearances))
    evil_avg_phi = to_glicko2_rd(average_rd(evil_appearances))

    # Process each player
    match.appearances.each do |appearance|
      player = appearance.player
      next unless player

      is_good = appearance.faction.good?
      won = (is_good && match.good_victory?) || (!is_good && !match.good_victory?)
      score = won ? 1.0 : 0.0

      # Get current ratings in Glicko-2 scale
      mu = to_glicko2_scale(player.glicko2_rating)
      phi = to_glicko2_rd(player.glicko2_rating_deviation)
      sigma = player.glicko2_volatility

      # Opponent team values
      opp_mu = is_good ? evil_avg_mu : good_avg_mu
      opp_phi = is_good ? evil_avg_phi : good_avg_phi

      # Calculate new ratings
      new_mu, new_phi, new_sigma = update_rating(mu, phi, sigma, opp_mu, opp_phi, score)

      # Convert back to Glicko scale
      new_rating = from_glicko2_scale(new_mu)
      new_rd = from_glicko2_rd(new_phi)
      rating_change = new_rating - player.glicko2_rating

      # Store snapshot on appearance
      appearance.glicko2_rating = player.glicko2_rating
      appearance.glicko2_rating_deviation = player.glicko2_rating_deviation
      appearance.glicko2_rating_change = rating_change

      # Update player
      player.glicko2_rating = new_rating
      player.glicko2_rating_deviation = new_rd
      player.glicko2_volatility = new_sigma
    end

    # Save all appearances and players
    match.appearances.each(&:save!)
    match.appearances.map(&:player).compact.uniq.each(&:save!)
  end

  # Glicko-2 scale conversions
  def to_glicko2_scale(rating)
    (rating - DEFAULT_RATING) / SCALE
  end

  def from_glicko2_scale(mu)
    mu * SCALE + DEFAULT_RATING
  end

  def to_glicko2_rd(rd)
    rd / SCALE
  end

  def from_glicko2_rd(phi)
    phi * SCALE
  end

  # Core Glicko-2 functions
  def g(phi)
    1.0 / Math.sqrt(1.0 + 3.0 * phi**2 / Math::PI**2)
  end

  def expected_score(mu, opp_mu, opp_phi)
    1.0 / (1.0 + Math.exp(-g(opp_phi) * (mu - opp_mu)))
  end

  def update_rating(mu, phi, sigma, opp_mu, opp_phi, score)
    # Step 3: Compute variance (v)
    g_opp = g(opp_phi)
    e = expected_score(mu, opp_mu, opp_phi)
    v = 1.0 / (g_opp**2 * e * (1.0 - e))

    # Step 4: Compute delta
    delta = v * g_opp * (score - e)

    # Step 5: Compute new volatility (simplified iteration)
    new_sigma = compute_new_volatility(sigma, phi, v, delta)

    # Step 6: Update phi to new pre-rating period value
    phi_star = Math.sqrt(phi**2 + new_sigma**2)

    # Step 7: Update rating and RD
    new_phi = 1.0 / Math.sqrt(1.0 / phi_star**2 + 1.0 / v)
    new_mu = mu + new_phi**2 * g_opp * (score - e)

    [ new_mu, new_phi, new_sigma ]
  end

  def compute_new_volatility(sigma, phi, v, delta)
    # Simplified volatility update - keep volatility stable for team games
    # The full iterative algorithm can be unstable with team averages
    # Instead, we use a simpler approach that still captures the essence

    # Clamp volatility to reasonable bounds
    [ sigma, 0.03, 0.1 ].sort[1]
  end

  def average_rating(appearances)
    ratings = appearances.map { |a| a.player&.glicko2_rating }.compact
    return DEFAULT_RATING if ratings.empty?
    ratings.sum / ratings.size.to_f
  end

  def average_rd(appearances)
    rds = appearances.map { |a| a.player&.glicko2_rating_deviation }.compact
    return DEFAULT_RD if rds.empty?
    rds.sum / rds.size.to_f
  end

  # Handle early leaver matches:
  # - Early leaver gets 0 rating change (no RD/volatility update)
  # - All other players get 70% of normal rating change (30% less)
  def store_early_leaver_appearances(match, good_appearances, evil_appearances)
    # Calculate team averages (in Glicko-2 scale)
    good_avg_mu = to_glicko2_scale(average_rating(good_appearances))
    good_avg_phi = to_glicko2_rd(average_rd(good_appearances))
    evil_avg_mu = to_glicko2_scale(average_rating(evil_appearances))
    evil_avg_phi = to_glicko2_rd(average_rd(evil_appearances))

    # Process each player
    match.appearances.each do |appearance|
      player = appearance.player
      next unless player

      is_good = appearance.faction.good?
      won = (is_good && match.good_victory?) || (!is_good && !match.good_victory?)
      score = won ? 1.0 : 0.0

      # Store current rating snapshot
      appearance.glicko2_rating = player.glicko2_rating
      appearance.glicko2_rating_deviation = player.glicko2_rating_deviation

      if appearance.is_early_leaver?
        # Early leaver gets 0 rating change
        appearance.glicko2_rating_change = 0
      else
        # Calculate normal rating change
        mu = to_glicko2_scale(player.glicko2_rating)
        phi = to_glicko2_rd(player.glicko2_rating_deviation)
        sigma = player.glicko2_volatility

        opp_mu = is_good ? evil_avg_mu : good_avg_mu
        opp_phi = is_good ? evil_avg_phi : good_avg_phi

        new_mu, new_phi, new_sigma = update_rating(mu, phi, sigma, opp_mu, opp_phi, score)

        new_rating = from_glicko2_scale(new_mu)
        new_rd = from_glicko2_rd(new_phi)
        rating_change = new_rating - player.glicko2_rating

        # Both winners and losers get 70% of normal rating change (30% less)
        reduced_change = (rating_change * 0.7).round(2)
        appearance.glicko2_rating_change = reduced_change
        player.glicko2_rating += reduced_change
        # Still update RD and volatility normally
        player.glicko2_rating_deviation = new_rd
        player.glicko2_volatility = new_sigma
      end
    end

    # Save all appearances and players
    match.appearances.each(&:save!)
    match.appearances.map(&:player).compact.uniq.each(&:save!)
  end
end
