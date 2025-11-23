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

  def recent_wins(days: 100)
    cutoff = days.days.ago
    appearances.joins(:match, :faction)
      .where(matches: { played_at: cutoff.. })
      .where(factions: { good: true }, matches: { good_victory: true })
      .or(appearances.joins(:match, :faction)
        .where(matches: { played_at: cutoff.. })
        .where(factions: { good: false }, matches: { good_victory: false }))
      .count
  end

  def recent_losses(days: 100)
    cutoff = days.days.ago
    recent_matches = matches.where(played_at: cutoff..).count
    recent_matches - recent_wins(days: days)
  end

  def recent_wins_with_faction(faction, days: 100)
    cutoff = days.days.ago
    won = faction.good? ? true : false
    appearances.joins(:match)
      .where(faction: faction)
      .where(matches: { played_at: cutoff.., good_victory: won })
      .count
  end

  def recent_losses_with_faction(faction, days: 100)
    cutoff = days.days.ago
    recent_with_faction = appearances.joins(:match)
      .where(faction: faction)
      .where(matches: { played_at: cutoff.. })
      .count
    recent_with_faction - recent_wins_with_faction(faction, days: days)
  end

  def wins_with_faction(faction)
    won = faction.good? ? true : false
    appearances.joins(:match)
      .where(faction: faction)
      .where(matches: { good_victory: won })
      .count
  end

  def losses_with_faction(faction)
    total_with_faction = appearances.where(faction: faction).count
    total_with_faction - wins_with_faction(faction)
  end

  def win_rate_with_faction(faction)
    total = appearances.where(faction: faction).count
    return 0 if total.zero?
    (wins_with_faction(faction).to_f / total * 100).round(1)
  end

  def observation_count
    Wc3statsReplay.all.count do |replay|
      replay.players.any? do |p|
        p["name"] == battletag && (p["slot"].nil? || p["slot"] > 9 || p["isWinner"].nil?)
      end
    end
  end
end
