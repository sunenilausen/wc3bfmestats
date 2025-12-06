class PlayerFactionStat < ApplicationRecord
  belongs_to :player
  belongs_to :faction

  scope :ranked, -> { where.not(rank: nil).order(:rank) }
  scope :for_faction, ->(faction) { where(faction: faction) }

  def win_rate
    return 0 if games_played.zero?
    (wins.to_f / games_played * 100).round(1)
  end

  def losses
    games_played - wins
  end
end
