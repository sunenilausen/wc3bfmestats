class Match < ApplicationRecord
  has_many :appearances
  has_many :players, through: :appearances

  accepts_nested_attributes_for :appearances# , allow_destroy: true
end
