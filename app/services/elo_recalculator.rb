class EloRecalculator
  K_FACTOR = 32
  DEFAULT_ELO = 1500

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
    # Reset all players to their seed ELO (or default)
    Player.find_each do |player|
      player.update!(elo_rating: player.elo_rating_seed || DEFAULT_ELO)
    end

    # Clear all appearance ELO data
    Appearance.update_all(elo_rating: nil, elo_rating_change: nil)
  end

  def recalculate_all_matches
    # Note: Cannot use find_each here because it ignores ORDER BY and processes by ID.
    # We need matches in chronological order for correct ELO calculation.
    # Uses Match.chronological scope which orders by:
    # 1. WC3 game version (major_version, build_version)
    # 2. Manual row_order
    # 3. Map version
    # 4. Played_at / created_at date
    # 5. Replay ID (upload order)
    # Ignored matches are excluded from ELO calculations.
    matches = Match.includes(appearances: [ :player, :faction ])
                   .where(ignored: false)
                   .chronological

    matches.each do |match|
      calculate_and_update_elo_ratings(match)
      @matches_processed += 1
    rescue StandardError => e
      @errors << "Match ##{match.id}: #{e.message}"
    end
  end

  def calculate_and_update_elo_ratings(match)
    return if match.appearances.empty?

    rating_changes = match.appearances.map do |appearance|
      player = appearance.player
      next unless player&.elo_rating

      opponent_avg = opponent_average_elo(match, appearance)
      next if opponent_avg.nil?

      expected_score = 1.0 / (1.0 + 10**((opponent_avg - player.elo_rating) / 400.0))
      actual_score = match.good_victory == appearance.faction.good ? 1 : 0

      elo_change = (K_FACTOR * (actual_score - expected_score)).round
      appearance.elo_rating_change = elo_change
      appearance.elo_rating = player.elo_rating
      elo_change
    end

    match.appearances.each_with_index do |appearance, index|
      next unless appearance.player && rating_changes[index]
      new_elo = appearance.player.elo_rating + rating_changes[index]
      appearance.player.update!(elo_rating: new_elo)
      appearance.save!
    end
  end

  def opponent_average_elo(match, appearance)
    opponent_appearances = match.appearances.reject { |a| a.faction.good == appearance.faction.good }
    return nil if opponent_appearances.empty?

    total_elo = opponent_appearances.sum { |a| a.player&.elo_rating.to_i }
    total_elo.to_f / opponent_appearances.size
  end
end
