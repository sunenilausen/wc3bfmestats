class LobbyObserver < ApplicationRecord
  belongs_to :lobby
  belongs_to :player
end
