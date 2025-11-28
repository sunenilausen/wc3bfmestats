# Recalculates Glicko-2 ratings for all matches in chronological order
#
# Usage:
#   result = Glicko2Recalculator.new.call
#   puts "Processed #{result.matches_processed} matches"
#   puts "Errors: #{result.errors}" if result.errors.any?
#
class Glicko2Recalculator
  DEFAULT_RATING = 1500.0
  DEFAULT_RD = 350.0
  DEFAULT_VOLATILITY = 0.06

  attr_reader :matches_processed, :errors

  def initialize
    @matches_processed = 0
    @errors = []
    @calculator = Glicko2Calculator.new
  end

  def call
    reset_all_ratings
    recalculate_all_matches
    self
  end

  private

  def reset_all_ratings
    # Reset all players to their seed Glicko-2 rating (or default)
    Player.find_each do |player|
      player.update!(
        glicko2_rating: player.glicko2_rating_seed || DEFAULT_RATING,
        glicko2_rating_deviation: DEFAULT_RD,
        glicko2_volatility: DEFAULT_VOLATILITY
      )
    end

    # Clear all appearance Glicko-2 data
    Appearance.update_all(
      glicko2_rating: nil,
      glicko2_rating_deviation: nil,
      glicko2_rating_change: nil
    )
  end

  def recalculate_all_matches
    # Note: Cannot use find_each here because it ignores ORDER BY and processes by ID.
    # We need matches in chronological order for correct Glicko-2 calculation.
    # Uses Match.chronological scope which orders by:
    # 1. WC3 game version (major_version, build_version)
    # 2. Manual row_order
    # 3. Map version
    # 4. Played_at / created_at date
    # 5. Replay ID (upload order)
    matches = Match.includes(appearances: [ :player, :faction ])
                   .where(ignored: false)
                   .chronological

    matches.each do |match|
      process_match(match)
      @matches_processed += 1
    rescue StandardError => e
      @errors << "Match ##{match.id}: #{e.message}"
    end
  end

  def process_match(match)
    # Calculate new ratings for all players in this match
    results = @calculator.calculate_match(match)
    return if results.empty?

    # Update appearances with rating snapshots
    match.appearances.each do |appearance|
      next unless appearance.player

      result = results[appearance.player_id]
      next unless result

      # Store the rating at match time (before update) and the change
      appearance.update!(
        glicko2_rating: appearance.player.glicko2_rating,
        glicko2_rating_deviation: appearance.player.glicko2_rating_deviation,
        glicko2_rating_change: result[:rating_change]
      )

      # Update player's current rating
      appearance.player.update!(
        glicko2_rating: result[:rating],
        glicko2_rating_deviation: result[:rd],
        glicko2_volatility: result[:volatility]
      )
    end
  end
end
