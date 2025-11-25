# Glicko-2 Rating System Calculator adapted for team games
#
# The Glicko-2 system uses three parameters per player:
# - Rating (r): The skill estimate (default 1500, same scale as ELO)
# - Rating Deviation (RD): Uncertainty in the rating (default 350, decreases with more games)
# - Volatility (σ): Expected fluctuation in rating (default 0.06)
#
# For team games, we use the average of opponent team ratings/RDs to compute updates.
# Each player on a team receives an individual update based on the match outcome.
#
# Reference: http://www.glicko.net/glicko/glicko2.pdf
#
class Glicko2Calculator
  # Glicko-2 constants
  TAU = 0.5           # System constant (constrains volatility change, typically 0.3-1.2)
  EPSILON = 0.000001  # Convergence tolerance for volatility iteration
  MAX_ITERATIONS = 100 # Maximum iterations for volatility calculation
  DEFAULT_RATING = 1500.0
  DEFAULT_RD = 350.0
  DEFAULT_VOLATILITY = 0.06
  MIN_RD = 30.0       # Minimum RD to prevent overconfidence
  MAX_RD = 350.0      # Maximum RD

  # Scaling factor to convert between Glicko-2 internal scale and display scale
  # Glicko-2 internally uses a scale where 1 unit ≈ 173.7178 rating points
  SCALE = 173.7178

  class PlayerRating
    attr_accessor :rating, :rd, :volatility

    def initialize(rating: DEFAULT_RATING, rd: DEFAULT_RD, volatility: DEFAULT_VOLATILITY)
      @rating = rating.to_f
      @rd = rd.to_f
      @volatility = volatility.to_f
    end

    # Convert to Glicko-2 scale (mu)
    def mu
      (rating - DEFAULT_RATING) / SCALE
    end

    # Convert to Glicko-2 scale (phi)
    def phi
      rd / SCALE
    end

    def to_h
      { rating: rating, rd: rd, volatility: volatility }
    end
  end

  # Calculate new ratings for all players in a match
  # Returns a hash of player_id => { rating:, rd:, volatility:, rating_change: }
  def calculate_match(match)
    return {} if match.appearances.empty?

    good_appearances = match.appearances.select { |a| a.faction.good? }
    evil_appearances = match.appearances.select { |a| !a.faction.good? }

    return {} if good_appearances.empty? || evil_appearances.empty?

    # Build team composites
    good_team = build_team_composite(good_appearances)
    evil_team = build_team_composite(evil_appearances)

    results = {}

    # Calculate updates for good team players
    good_appearances.each do |appearance|
      next unless appearance.player
      outcome = match.good_victory? ? 1.0 : 0.0
      results[appearance.player_id] = calculate_player_update(
        appearance.player, evil_team, outcome
      )
    end

    # Calculate updates for evil team players
    evil_appearances.each do |appearance|
      next unless appearance.player
      outcome = match.good_victory? ? 0.0 : 1.0
      results[appearance.player_id] = calculate_player_update(
        appearance.player, good_team, outcome
      )
    end

    results
  end

  private

  # Build a composite "opponent" from a team of players
  # Uses average rating and pooled RD
  def build_team_composite(appearances)
    players_with_ratings = appearances.select { |a| a.player&.glicko2_rating }
    return PlayerRating.new if players_with_ratings.empty?

    ratings = players_with_ratings.map { |a| a.player.glicko2_rating }
    rds = players_with_ratings.map { |a| a.player.glicko2_rating_deviation || DEFAULT_RD }

    # Average rating for the team
    avg_rating = ratings.sum / ratings.size

    # Pooled RD: sqrt of average of squared RDs
    # This represents the combined uncertainty of the team
    pooled_rd = Math.sqrt(rds.map { |r| r**2 }.sum / rds.size)

    # Average volatility
    volatilities = players_with_ratings.map { |a| a.player.glicko2_volatility || DEFAULT_VOLATILITY }
    avg_volatility = volatilities.sum / volatilities.size

    PlayerRating.new(rating: avg_rating, rd: pooled_rd, volatility: avg_volatility)
  end

  # Calculate the rating update for a single player against an opponent composite
  def calculate_player_update(player, opponent, outcome)
    # Current player rating
    current_rating = player.glicko2_rating || DEFAULT_RATING
    current_rd = player.glicko2_rating_deviation || DEFAULT_RD
    current_volatility = player.glicko2_volatility || DEFAULT_VOLATILITY

    # Clamp values to reasonable ranges
    current_rd = current_rd.clamp(MIN_RD, MAX_RD)
    current_volatility = current_volatility.clamp(0.01, 0.15)

    pr = PlayerRating.new(
      rating: current_rating,
      rd: current_rd,
      volatility: current_volatility
    )

    old_rating = pr.rating

    # Convert to Glicko-2 scale
    mu = pr.mu
    phi = pr.phi
    sigma = pr.volatility

    # Opponent on Glicko-2 scale
    opp_rd = opponent.rd.clamp(MIN_RD, MAX_RD)
    mu_j = (opponent.rating - DEFAULT_RATING) / SCALE
    phi_j = opp_rd / SCALE

    # Step 3: Compute g(φ) and E(μ, μj, φj)
    g_phi_j = g_function(phi_j)
    e_value = e_function(mu, mu_j, phi_j)

    # Clamp e_value to avoid division issues
    e_value = e_value.clamp(0.0001, 0.9999)

    # Step 4: Compute variance (v)
    v = 1.0 / (g_phi_j**2 * e_value * (1 - e_value))

    # Step 5: Compute delta (Δ)
    delta = v * g_phi_j * (outcome - e_value)

    # Step 6: Compute new volatility (σ')
    new_sigma = compute_new_volatility(sigma, phi, v, delta)

    # Clamp new_sigma to reasonable range
    new_sigma = new_sigma.clamp(0.01, 0.15)

    # Step 7: Update phi to phi*
    phi_star = Math.sqrt(phi**2 + new_sigma**2)

    # Step 8: Update phi' and mu'
    new_phi = 1.0 / Math.sqrt(1.0 / phi_star**2 + 1.0 / v)
    new_mu = mu + new_phi**2 * g_phi_j * (outcome - e_value)

    # Convert back to rating scale
    new_rating = new_mu * SCALE + DEFAULT_RATING
    new_rd = new_phi * SCALE

    # Clamp to reasonable ranges
    new_rd = new_rd.clamp(MIN_RD, MAX_RD)
    new_rating = new_rating.clamp(100.0, 3500.0)

    {
      rating: new_rating.round(2),
      rd: new_rd.round(2),
      volatility: new_sigma.round(6),
      rating_change: (new_rating - old_rating).round(2)
    }
  end

  # g(φ) function - reduces impact of opponents with high uncertainty
  def g_function(phi)
    1.0 / Math.sqrt(1.0 + 3.0 * phi**2 / Math::PI**2)
  end

  # E(μ, μj, φj) - expected score
  def e_function(mu, mu_j, phi_j)
    exponent = -g_function(phi_j) * (mu - mu_j)
    # Clamp exponent to avoid overflow
    exponent = exponent.clamp(-20, 20)
    1.0 / (1.0 + Math.exp(exponent))
  end

  # Compute new volatility using iterative algorithm (Step 6)
  def compute_new_volatility(sigma, phi, v, delta)
    # Initial values
    a = Math.log(sigma**2)
    delta_sq = delta**2
    phi_sq = phi**2

    # Define f(x)
    f = lambda do |x|
      return 0.0 if x.abs > 100 # Prevent overflow
      ex = Math.exp(x)
      denom = phi_sq + v + ex
      return 0.0 if denom <= 0 # Prevent division by zero
      term1 = (ex * (delta_sq - phi_sq - v - ex)) / (2.0 * denom**2)
      term2 = (x - a) / TAU**2
      term1 - term2
    end

    # Set initial bounds
    if delta_sq > phi_sq + v
      diff = delta_sq - phi_sq - v
      b = diff > 0 ? Math.log(diff) : a - TAU
    else
      k = 1
      while f.call(a - k * TAU) < 0 && k < MAX_ITERATIONS
        k += 1
      end
      b = a - k * TAU
    end

    # Iterative algorithm to find volatility
    fa = f.call(a)
    fb = f.call(b)

    iterations = 0
    while (b - a).abs > EPSILON && iterations < MAX_ITERATIONS
      iterations += 1

      # Avoid division by zero
      if (fb - fa).abs < EPSILON
        break
      end

      c = a + (a - b) * fa / (fb - fa)

      # Clamp c to reasonable range
      c = c.clamp(-50, 50)

      fc = f.call(c)

      if fc * fb <= 0
        a = b
        fa = fb
      else
        fa /= 2.0
      end

      b = c
      fb = fc
    end

    result = Math.exp(a / 2.0)
    # Return clamped volatility
    result.clamp(0.01, 0.15)
  end
end
