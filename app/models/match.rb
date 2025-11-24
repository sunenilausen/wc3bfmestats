class Match < ApplicationRecord
  has_many :appearances, dependent: :destroy
  has_many :players, through: :appearances
  belongs_to :wc3stats_replay, optional: true

  accepts_nested_attributes_for :appearances# , allow_destroy: true

  scope :by_played_at, ->(direction = :asc) {
    order(Arel.sql("COALESCE(matches.played_at, matches.created_at) #{direction.to_s.upcase}"))
  }

  def played_at_formatted
    return played_at.strftime("%Y-%m-%d %H:%M:%S") if played_at.present?
    created_at.strftime("%Y-%m-%d %H:%M:%S")
  end
end
