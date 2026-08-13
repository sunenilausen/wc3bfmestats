module LobbiesHelper
  FORM_BADGE_CLASSES = {
    PlayerForm::WIN => "bg-green-500",
    PlayerForm::LOSS => "bg-red-500",
    PlayerForm::DRAW => "bg-gray-400"
  }.freeze

  # Last few results as a row of coloured badges, most recent first
  def player_form_badges(results)
    return content_tag(:span, "-", class: "text-gray-400") if results.blank?

    badges = results.map do |result|
      content_tag(:span, result,
        class: "inline-flex items-center justify-center w-4 h-4 rounded-sm text-[10px] font-bold text-white #{FORM_BADGE_CLASSES[result]}")
    end

    content_tag(:span, safe_join(badges, " ".html_safe), class: "inline-flex gap-0.5", title: "Last #{results.size} results, most recent first")
  end

  # Flag players worth knowing about before you pick them: a poor overall leave
  # record, or a leave in their last few games
  LEAVE_PCT_WARNING = 5

  def leaver_warning?(leave_pct, recent_leaves)
    leave_pct.to_f > LEAVE_PCT_WARNING || recent_leaves.to_i.positive?
  end

  def leaver_warning_badge(leave_pct, recent_leaves)
    return "".html_safe unless leaver_warning?(leave_pct, recent_leaves)

    reasons = []
    reasons << "leaves #{leave_pct.round}% of games" if leave_pct.to_f > LEAVE_PCT_WARNING
    reasons << "left #{recent_leaves} of the last #{PlayerForm::GAMES}" if recent_leaves.to_i.positive?

    content_tag(:span, "⚠",
      class: "text-yellow-600 text-xs cursor-help",
      title: reasons.join(", "))
  end

  # Performance score and contribution rank, shown on hover over the rating
  def rating_tooltip(ml_score, faction_perf, avg_rank, faction_rank)
    perf = [ format_perf_score(ml_score&.round), (format_perf_score(faction_perf) if faction_perf) ].compact.join(" / ")
    rank = [ avg_rank&.round(1), faction_rank&.round(1) ].compact.join(" / ")

    parts = [ ("PERF #{perf} (overall / faction)" if perf.present?) ]
    parts << "Rank #{rank} (overall / faction, 1 = best)" if rank.present?

    parts.compact.join(" - ")
  end

  def short_time_ago(time)
    return "-" unless time

    seconds = Time.current - time
    minutes = seconds / 60
    hours = minutes / 60
    days = hours / 24
    weeks = days / 7
    months = days / 30
    years = days / 365

    if seconds < 60
      "< 1m"
    elsif minutes < 60
      "#{minutes.round}m"
    elsif hours < 24
      "< 1d"
    elsif days < 7
      "#{days.round}d"
    elsif weeks < 4
      "#{weeks.round}w"
    elsif months < 12
      "#{months.round}mo"
    else
      "#{years.round}y"
    end
  end
end
