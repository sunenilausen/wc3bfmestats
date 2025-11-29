# Determines player tier based on ML score
class PlayerTier
  TIERS = [
    { name: "Newcomer", min: 0, max: 40, color: "gray" },
    { name: "Intermediate", min: 40, max: 47, color: "green" },
    { name: "Advanced", min: 47, max: 53, color: "blue" },
    { name: "Expert", min: 53, max: 62, color: "purple" },
    { name: "Hardcore", min: 62, max: 100, color: "red" }
  ].freeze

  class << self
    def for_score(ml_score)
      return nil if ml_score.nil?

      tier = TIERS.find { |t| ml_score >= t[:min] && ml_score < t[:max] }
      tier || TIERS.last # Default to highest tier if score >= 100
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
  end
end
