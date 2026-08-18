module FactionsHelper
  # Nicknames for the players in a ring-event match list, in one query.
  def ring_match_players(*match_lists)
    ids = match_lists.compact.flatten.filter_map { |m| m[:player_id] }.uniq
    return {} if ids.empty?

    Player.where(id: ids).pluck(:id, :nickname).to_h
  end

  # One line per game behind a rare ring stat: when, who, and how it went.
  def ring_match_summary(match, players)
    parts = [ match[:played_at]&.strftime("%Y-%m-%d"), match[:map_version], players[match[:player_id]] ]
    parts << if match[:draw]
      "draw"
    else
      match[:won] ? "won" : "lost"
    end
    parts.compact.join(" · ")
  end
end
