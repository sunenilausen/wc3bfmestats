class Match < ApplicationRecord
  has_many :appearances, dependent: :destroy
  has_many :players, through: :appearances

  accepts_nested_attributes_for :appearances# , allow_destroy: true
end
