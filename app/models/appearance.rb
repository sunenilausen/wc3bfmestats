class Appearance < ApplicationRecord
  belongs_to :player
  belongs_to :faction
  belongs_to :match
  # belongs_to :wc3stats_replay
end
