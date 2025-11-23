class LobbyPlayer < ApplicationRecord
  belongs_to :lobby
  belongs_to :player, optional: true
  belongs_to :faction
end
