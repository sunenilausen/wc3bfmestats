module ApplicationHelper
  def tier_badge(_ml_score)
    "" # Tier labels disabled
  end

  def ml_score_with_tier(ml_score)
    return "-" if ml_score.nil?
    ml_score.to_s
  end

  # The CR adjustments behind a rating, as "(-36)" next to it. Nothing when the
  # adjustments cancel out to zero. Hovering explains where the number came from.
  def rating_adjustment_tag(breakdown, faction_name: nil, **html_options)
    return "".html_safe unless breakdown&.any?

    content_tag(:span, "(#{signed_cr(breakdown.total)})",
      { class: "text-gray-500", title: rating_adjustment_title(breakdown, faction_name: faction_name) }.merge(html_options))
  end

  # Every part of the adjustment, for a tooltip
  def rating_adjustment_title(breakdown, faction_name: nil)
    parts = []
    parts << "new player #{signed_cr(breakdown.new_player)}" if breakdown.new_player.round != 0
    parts << "unfamiliar faction #{signed_cr(breakdown.familiarity)}" if breakdown.familiarity.round != 0
    if breakdown.faction.round != 0
      parts << "#{faction_name || 'faction'} impact #{signed_cr(breakdown.faction)}"
    end

    "Counts as #{breakdown.weighted_cr.round} toward the team#{" - #{parts.join(', ')}" if parts.any?}"
  end

  def signed_cr(value)
    "#{value.round >= 0 ? '+' : ''}#{value.round}"
  end
end
