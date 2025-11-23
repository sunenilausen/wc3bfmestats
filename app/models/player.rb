class Player < ApplicationRecord
  has_many :appearances
  has_many :matches, through: :appearances
  has_many :lobby_players
  has_many :lobbies, through: :lobby_players

  def wins
    appearances.joins(:match, :faction)
      .where(factions: { good: true }, matches: { good_victory: true })
      .or(appearances.joins(:match, :faction)
        .where(factions: { good: false }, matches: { good_victory: false }))
      .count
  end

  def losses
    matches.count - wins
  end

  def observation_count
    Wc3statsReplay.all.count do |replay|
      replay.players.any? do |p|
        p["name"] == battletag && (p["slot"].nil? || p["slot"] > 9 || p["isWinner"].nil?)
      end
    end
  end
end
