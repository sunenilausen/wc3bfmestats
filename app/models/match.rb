class Match < ApplicationRecord
  has_many :appearances, dependent: :destroy
  has_many :players, through: :appearances
  belongs_to :wc3stats_replay, optional: true

  accepts_nested_attributes_for :appearances# , allow_destroy: true

  scope :by_played_at, ->(direction = :asc) {
    order(Arel.sql("COALESCE(matches.played_at, matches.created_at) #{direction.to_s.upcase}"))
  }

  # Chronological ordering for ELO/Glicko-2 calculations
  # Order of importance (ascending):
  # 1. WC3 game version (major_version, build_version)
  # 2. Manual row_order (for fine-tuning)
  # 3. Map version (parsed from map filename, e.g., "4.5e")
  # 4. File date / played_at date
  # 5. Replay ID (upload order from wc3stats)
  scope :chronological, -> {
    order(
      Arel.sql(<<~SQL.squish)
        COALESCE(matches.major_version, 0) ASC,
        COALESCE(matches.build_version, 0) ASC,
        COALESCE(matches.row_order, 999999) ASC,
        matches.map_version ASC NULLS FIRST,
        COALESCE(matches.played_at, matches.created_at) ASC,
        COALESCE(matches.wc3stats_replay_id, matches.id) ASC
      SQL
    )
  }

  # Parse map version string for comparison (e.g., "4.5e" -> [4, 5, "e"])
  def parsed_map_version
    return nil unless map_version

    match = map_version.match(/(\d+)\.(\d+)([a-z])?/i)
    return nil unless match

    [ match[1].to_i, match[2].to_i, match[3]&.downcase || "" ]
  end

  def played_at_formatted
    return played_at.strftime("%Y-%m-%d %H:%M:%S") if played_at.present?
    created_at.strftime("%Y-%m-%d %H:%M:%S")
  end
end
