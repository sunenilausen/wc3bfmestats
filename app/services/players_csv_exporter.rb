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
    [ "nickname", "battletag", "custom_rating", "ml_score", "matches", "last_appearance", "wins", "losses", "win_rate" ]
  end

  def players
    Player.includes(:appearances, :matches).order(custom_rating: :desc)
  end

  def row_for(player)
    [
      player.nickname,
      player.battletag,
      player.custom_rating&.round,
      player.ml_score&.round(1),
      player.appearances.size,
      last_appearance(player),
      player.wins,
      player.losses,
      win_rate(player)
    ]
  end

  def last_appearance(player)
    last_match = player.matches.by_uploaded_at(:desc).first
    last_match&.uploaded_at_formatted || "N/A"
  end

  def win_rate(player)
    total = player.appearances.size
    return "0%" if total.zero?
    "#{(player.wins.to_f / total * 100).round(1)}%"
  end
end
