class Match < ApplicationRecord
  has_many :appearances, dependent: :destroy
  has_many :players, through: :appearances
  belongs_to :wc3stats_replay, optional: true

  accepts_nested_attributes_for :appearances# , allow_destroy: true

  # Invalidate stats cache when matches change
  after_commit :invalidate_stats_cache

  def invalidate_stats_cache
    StatsCacheKey.invalidate!
  end

  # Balanced games: prediction between 45-55%
  scope :balanced, -> {
    where("predicted_good_win_pct >= 45 AND predicted_good_win_pct <= 55")
  }

  # Imbalanced games: prediction outside 45-55%
  scope :imbalanced, -> {
    where("predicted_good_win_pct < 45 OR predicted_good_win_pct > 55")
  }

  scope :by_uploaded_at, ->(direction = :asc) {
    case direction.to_s.downcase
    when "desc"
      order(Arel.sql("matches.uploaded_at DESC NULLS LAST"))
    else
      order(Arel.sql("matches.uploaded_at ASC NULLS LAST"))
    end
  }

  # Chronological ordering for ELO/Glicko-2 calculations
  # Order of importance (ascending):
  # 1. Played_at date (from replay filename - MOST IMPORTANT)
  # 2. WC3 game version (major_version, build_version)
  # 3. Manual row_order (for fine-tuning)
  # 4. Map version (parsed from map filename, e.g., "4.5e")
  # 5. Uploaded_at (when replay was uploaded to wc3stats)
  # 6. Replay ID (upload order from wc3stats)
  scope :chronological, -> {
    order(
      Arel.sql(<<~SQL.squish)
        matches.played_at ASC NULLS LAST,
        COALESCE(matches.major_version, 0) ASC,
        COALESCE(matches.build_version, 0) ASC,
        COALESCE(matches.row_order, 999999) ASC,
        matches.map_version ASC NULLS FIRST,
        matches.uploaded_at ASC NULLS LAST,
        COALESCE(matches.wc3stats_replay_id, matches.id) ASC
      SQL
    )
  }

  scope :reverse_chronological, -> {
    order(
      Arel.sql(<<~SQL.squish)
        matches.played_at DESC NULLS FIRST,
        COALESCE(matches.major_version, 0) DESC,
        COALESCE(matches.build_version, 0) DESC,
        COALESCE(matches.row_order, 999999) DESC,
        matches.map_version DESC NULLS LAST,
        matches.uploaded_at DESC NULLS FIRST,
        COALESCE(matches.wc3stats_replay_id, matches.id) DESC
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

  def uploaded_at_formatted
    return uploaded_at.strftime("%Y-%m-%d %H:%M:%S") if uploaded_at.present?
    "Unknown"
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

  # Use checksum as URL param instead of id
  def to_param
    checksum || id.to_s
  end

  def checksum
    wc3stats_replay&.replay_hash
  end

  # Find by checksum or id
  def self.find_by_checksum_or_id(param)
    # First try to find by checksum (via wc3stats_replay)
    replay = Wc3statsReplay.find_by("body->>'hash' = ?", param)
    return replay.match if replay&.match

    # If not found by checksum, try by id
    find_by(id: param) if param.to_s =~ /\A\d+\z/
  end
end
