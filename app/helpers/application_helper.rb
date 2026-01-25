module ApplicationHelper
  def tier_badge(_ml_score)
    "" # Tier labels disabled
  end

  def ml_score_with_tier(ml_score)
    return "-" if ml_score.nil?
    ml_score.to_s
  end
end
