class Match < ApplicationRecord
  has_many :appearances, dependent: :destroy
  has_many :players, through: :appearances
  belongs_to :wc3stats_replay, optional: true

  accepts_nested_attributes_for :appearances# , allow_destroy: true

  scope :by_played_at, ->(direction = :asc) {
    order(Arel.sql("matches.played_at #{direction.to_s.upcase} NULLS LAST"))
  }

  # Chronological ordering for ELO/Glicko-2 calculations
  # Order of importance (ascending):
  # 1. WC3 game version (major_version, build_version)
  # 2. Manual row_order (for fine-tuning)
  # 3. Map version (parsed from map filename, e.g., "4.5e")
  # 4. Played_at date (from replay file path or playedOn timestamp)
  # 5. Replay ID (upload order from wc3stats)
  scope :chronological, -> {
    order(
      Arel.sql(<<~SQL.squish)
        COALESCE(matches.major_version, 0) ASC,
        COALESCE(matches.build_version, 0) ASC,
        COALESCE(matches.row_order, 999999) ASC,
        matches.map_version ASC NULLS FIRST,
        matches.played_at ASC NULLS LAST,
        COALESCE(matches.wc3stats_replay_id, matches.id) ASC
      SQL
    )
  }

  # Parse map version string for comparison
  # Examples:
  #   "4.5" -> [4, 5, "", ""]
  #   "4.5e" -> [4, 5, "e", ""]
  #   "4.3gObs" -> [4, 3, "g", "obs"]
  #   "4.1Test3" -> [4, 1, "", "test3"]
  # Sorting: major, minor, letter, suffix (alphabetically)
  def parsed_map_version
    return nil unless map_version

    # Match: major.minor + optional lowercase letter + optional suffix (Obs, Test#, etc.)
    # The lowercase letter is only captured if followed by uppercase or end of string
    match_data = map_version.match(/(\d+)\.(\d+)([a-z](?=[A-Z]|$))?(.+)?/)
    return nil unless match_data

    [
      match_data[1].to_i,
      match_data[2].to_i,
      match_data[3] || "",
      match_data[4]&.downcase || ""
    ]
  end

  def played_at_formatted
    return played_at.strftime("%Y-%m-%d %H:%M:%S") if played_at.present?
    "Unknown"
  end

  # Check if victory was manually overridden from replay data
  def victory_overridden?
    return false unless wc3stats_replay.present?
    good_victory != wc3stats_replay.good_victory?
  end
end
