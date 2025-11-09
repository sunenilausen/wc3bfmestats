class Faction < ApplicationRecord
  COLORS = %w[red blue teal purple yellow green gray lightblue darkgreen brown].freeze
  NAMES = [ "Gondor", "Rohan", "Dol Amroth", "Fellowship", "Fangorn", "Isengard", "Easterlings", "Harad", "Nazgul", "Mordor" ].freeze

  validates :name, presence: true, uniqueness: true
  validates :color, presence: true, inclusion: { in: COLORS }
end
