require "csv"

class PlayersCsvExporter
  def self.call
    new.call
  end

  def call
    CSV.generate do |csv|
      csv << headers
      players.each do |player|
        csv << row_for(player)
      end
    end
  end

  private

  def headers
    ["nickname", "battletag", "elo_rating", "matches", "last_appearance", "wins", "losses", "win_rate"]
  end

  def players
    Player.includes(:appearances, :matches).order(elo_rating: :desc)
  end

  def row_for(player)
    [
      player.nickname,
      player.battletag,
      player.elo_rating&.round,
      player.appearances.size,
      last_appearance(player),
      player.wins,
      player.losses,
      win_rate(player)
    ]
  end

  def last_appearance(player)
    last_match = player.matches.by_played_at(:desc).first
    last_match&.played_at_formatted || "N/A"
  end

  def win_rate(player)
    total = player.appearances.size
    return "0%" if total.zero?
    "#{(player.wins.to_f / total * 100).round(1)}%"
  end
end
