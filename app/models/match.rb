class Match < ApplicationRecord
  has_many :appearances
  has_many :players, through: :appearances
end
