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
end
