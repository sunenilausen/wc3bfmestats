module ApplicationHelper
  def tier_badge(ml_score)
    return "" if ml_score.nil?

    tier_name = PlayerTier.name_for_score(ml_score)
    css_classes = PlayerTier.css_classes(ml_score)

    content_tag(:span, tier_name, class: "#{css_classes} text-xs px-1.5 py-0.5 rounded font-medium")
  end

  def ml_score_with_tier(ml_score)
    return "-" if ml_score.nil?

    "#{ml_score} #{tier_badge(ml_score)}".html_safe
  end
end
