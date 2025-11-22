class Appearance < ApplicationRecord
  belongs_to :player
  belongs_to :faction
  belongs_to :match
end
