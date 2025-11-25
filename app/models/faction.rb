class Faction < ApplicationRecord
  COLORS = %w[red blue teal purple yellow green gray lightblue darkgreen brown].freeze
  NAMES = [ "Gondor", "Rohan", "Dol Amroth", "Fellowship", "Fangorn", "Isengard", "Easterlings", "Harad", "Nazgul", "Mordor" ].freeze

  COLOR_HEX = {
    "red" => "#ff0303",
    "blue" => "#0042ff",
    "teal" => "#1ce6b9",
    "purple" => "#540081",
    "yellow" => "#fffc00",
    "green" => "#20c000",
    "gray" => "#959697",
    "lightblue" => "#7ebff1",
    "darkgreen" => "#106246",
    "brown" => "#4e2a04"
  }.freeze

  validates :name, presence: true, uniqueness: true
  validates :color, presence: true, inclusion: { in: COLORS }

  has_many :appearances

  def color_hex
    COLOR_HEX[color] || "#888888"
  end
end
