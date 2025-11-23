class Lobby < ApplicationRecord
  has_many :lobby_players, dependent: :destroy
  has_many :players, through: :lobby_players
end
