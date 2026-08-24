module PlayersHelper
  # Color class for performance score (centered on 0)
  # Positive = above average (green), Negative = below average (red)
  def ml_score_color_class(score)
    score ||= 0.0
    if score >= 5
      "text-green-600"
    elsif score <= -5
      "text-red-600"
    else
      "text-gray-600"
    end
  end

  # Format performance score with + sign for positive values
  def format_perf_score(score)
    return "-" if score.nil?
    score >= 0 ? "+#{score}" : score.to_s
  end

  # Display player name with alternative name if present
  # Returns: "Nickname (AltName)" or just "Nickname"
  def player_display_name(player)
    return "" unless player
    if player.alternative_name.present?
      "#{player.nickname} (#{player.alternative_name})"
    else
      player.nickname
    end
  end

  # Display player name with alternative name in a styled format
  # Returns HTML with alt name in gray
  def player_display_name_html(player)
    return "" unless player
    if player.alternative_name.present?
      safe_join([
        player.nickname,
        " ",
        content_tag(:span, "(#{player.alternative_name})", class: "text-gray-500")
      ])
    else
      player.nickname
    end
  end

  # Admins can flag someone who trolls or ruins games. It is a warning to whoever
  # is reading, never an input to a rating - the note is the whole point, so it
  # rides along as the tooltip.
  # Mirrored by flagHtml() in lobbies/edit.html.erb for the JS-rebuilt slots.
  def player_flag_icon(player, extra_class: "")
    return "".html_safe unless player&.flagged?

    content_tag(:span, "\u{1F6A9}",
      class: "text-xs cursor-help #{extra_class}".strip,
      title: player.flag_reason)
  end

  # Games a player took part in that the rating system had to throw away, because
  # the map never reported a result. Shown next to their match count so someone
  # with a long unrated history does not read as a complete newcomer.
  def unrated_games_badge(player)
    count = player.unrated_games.to_i
    return "".html_safe if count.zero?

    content_tag(:span, "+#{count} unrated",
      class: "ml-1 text-xs text-gray-500 cursor-help",
      title: "#{count} #{"game".pluralize(count)} where the map saved no result, so they could not be rated. " \
             "They count as evidence this player has played, not as evidence of how well.")
  end
end
