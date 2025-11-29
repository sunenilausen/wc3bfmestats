module PlayersHelper
  def ml_score_color_class(score)
    score ||= 50.0
    if score >= 55
      "text-green-600"
    elsif score <= 45
      "text-red-600"
    else
      "text-gray-600"
    end
  end
end
