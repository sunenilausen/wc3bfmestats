# Determines player tier based on ML score using dynamic percentile thresholds
class PlayerTier
  TIER_CONFIG = [
    { key: :newcomer, name: "Newcomer", color: "gray" },
    { key: :intermediate, name: "Intermediate", color: "green" },
    { key: :advanced, name: "Advanced", color: "blue" },
    { key: :expert, name: "Expert", color: "purple" },
    { key: :hardcore, name: "Hardcore", color: "red" }
  ].freeze

  class << self
    def for_score(ml_score)
      return nil if ml_score.nil?

      thresholds = PlayerTierCalculator.current_thresholds
      tier_key = determine_tier_key(ml_score, thresholds)
      tier_config = TIER_CONFIG.find { |t| t[:key] == tier_key }

      return nil unless tier_config

      {
        name: tier_config[:name],
        color: tier_config[:color],
        min: thresholds.dig(tier_key, :min),
        max: thresholds.dig(tier_key, :max)
      }
    end

    def name_for_score(ml_score)
      for_score(ml_score)&.dig(:name)
    end

    def color_for_score(ml_score)
      for_score(ml_score)&.dig(:color)
    end

    # Returns tailwind color classes for the tier
    def css_classes(ml_score)
      color = color_for_score(ml_score)
      case color
      when "gray"
        "text-gray-500 bg-gray-100"
      when "green"
        "text-green-700 bg-green-100"
      when "blue"
        "text-blue-700 bg-blue-100"
      when "purple"
        "text-purple-700 bg-purple-100"
      when "red"
        "text-red-700 bg-red-100"
      else
        "text-gray-500 bg-gray-100"
      end
    end

    # Get current tier thresholds for display
    def current_thresholds
      PlayerTierCalculator.current_thresholds
    end

    private

    def determine_tier_key(ml_score, thresholds)
      # Check from highest tier to lowest
      return :hardcore if ml_score >= thresholds.dig(:hardcore, :min)
      return :expert if ml_score >= thresholds.dig(:expert, :min)
      return :advanced if ml_score >= thresholds.dig(:advanced, :min)
      return :intermediate if ml_score >= thresholds.dig(:intermediate, :min)

      :newcomer
    end
  end
end
