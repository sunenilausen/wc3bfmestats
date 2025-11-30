# Calculates dynamic tier thresholds based on ML score percentiles
# Tiers are based on the distribution of active players (those with matches)
class PlayerTierCalculator
  # Percentile boundaries for each tier (from lowest to highest)
  # Bottom 20% = Newcomer, 20-40% = Intermediate, 40-60% = Advanced, 60-80% = Expert, Top 20% = Hardcore
  TIER_PERCENTILES = {
    newcomer: 0,        # 0th percentile (bottom)
    intermediate: 20,   # 20th percentile
    advanced: 40,       # 40th percentile
    expert: 60,         # 60th percentile
    hardcore: 80        # 80th percentile (top 20%)
  }.freeze

  TIER_CONFIG = [
    { key: :newcomer, name: "Newcomer", color: "gray", percentile_min: 0 },
    { key: :intermediate, name: "Intermediate", color: "green", percentile_min: 20 },
    { key: :advanced, name: "Advanced", color: "blue", percentile_min: 40 },
    { key: :expert, name: "Expert", color: "purple", percentile_min: 60 },
    { key: :hardcore, name: "Hardcore", color: "red", percentile_min: 80 }
  ].freeze

  class << self
    def call
      new.call
    end

    def current_thresholds
      cached = Rails.cache.read("player_tier_thresholds")
      return cached if cached.present?

      # Calculate and cache if not present
      call
    end
  end

  def call
    thresholds = calculate_thresholds
    Rails.cache.write("player_tier_thresholds", thresholds, expires_in: 24.hours)
    thresholds
  end

  private

  def calculate_thresholds
    # Get ML scores for active players (those who have played at least one non-ignored match)
    scores = Player.joins(:matches)
      .where(matches: { ignored: false })
      .where.not(ml_score: nil)
      .distinct
      .pluck(:ml_score)
      .sort

    return default_thresholds if scores.empty?

    # Calculate percentile values
    {
      newcomer: { min: 0, max: percentile_value(scores, 20) },
      intermediate: { min: percentile_value(scores, 20), max: percentile_value(scores, 40) },
      advanced: { min: percentile_value(scores, 40), max: percentile_value(scores, 60) },
      expert: { min: percentile_value(scores, 60), max: percentile_value(scores, 80) },
      hardcore: { min: percentile_value(scores, 80), max: 100 },
      calculated_at: Time.current,
      player_count: scores.size
    }
  end

  def percentile_value(sorted_scores, percentile)
    return 0 if sorted_scores.empty?

    # Calculate the index for this percentile
    index = (percentile / 100.0 * (sorted_scores.size - 1)).round
    sorted_scores[index].round(1)
  end

  def default_thresholds
    # Fallback static thresholds if no data
    {
      newcomer: { min: 0, max: 40 },
      intermediate: { min: 40, max: 47 },
      advanced: { min: 47, max: 53 },
      expert: { min: 53, max: 62 },
      hardcore: { min: 62, max: 100 },
      calculated_at: nil,
      player_count: 0
    }
  end
end
