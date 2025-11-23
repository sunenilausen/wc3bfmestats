class Lobby < ApplicationRecord
  has_many :lobby_players, dependent: :destroy
  has_many :players, through: :lobby_players
  has_and_belongs_to_many :observers, class_name: "Player", join_table: "lobby_observers"
end
