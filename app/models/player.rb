class Player < ApplicationRecord
  has_many :appearances
  has_many :matches, through: :appearances
end
