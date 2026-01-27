class Wc3statsReplay < ApplicationRecord
  has_one :match, dependent: :nullify
  validates :wc3stats_replay_id, presence: true, uniqueness: true

  # Access parsed body data
  def replay_data
    body
  end

  # Game metadata
  def game_name
    body&.dig("name")
  end

  def map_name
    body&.dig("map")
  end

  # Game version from replay header (e.g., 10100)
  def major_version
    body&.dig("data", "header", "majorVersion")
  end

  # Build version from replay header (e.g., 6116)
  def build_version
    body&.dig("data", "header", "buildVersion")
  end

  # Map file name with version (e.g., "BFME4.5e.w3x")
  def map_file_name
    body&.dig("data", "game", "map")
  end

  # Parse map version from filename (e.g., "BFME4.5e.w3x" -> "4.5e", "BFME4.3gObs.w3x" -> "4.3gObs")
  # Also handles: "BFME3.8Beta3.w3x" -> "3.8Beta3", "BFME4.1Test3.w3x" -> "4.1Test3"
  # Returns nil if not parseable or for .w3m files
  def map_version
    return nil unless map_file_name

    # Only match .w3x files (exclude .w3m like BFME7.4_GFINALFOREVERDONE.w3m)
    # Captures everything after "BFME" and before ".w3x"
    if map_file_name =~ /BFME(\d+\.\d+[^.]*)\.(w3x)/i
      $1
    end
  end

  def test_map?
    map_file_name&.match?(/test/i)
  end

  # Check if the game has fewer than 10 active players (slots 0-9 with win/loss status)
  def incomplete_game?
    active_player_count < 10
  end

  def active_player_count
    players.count do |p|
      slot = p["slot"]
      slot.present? && slot >= 0 && slot <= 9 && !p["isWinner"].nil?
    end
  end

  def game_length
    body&.dig("length")
  end

  # Returns the best estimate of when the game was actually played
  # Priority:
  # 1. Parse date from filename if it matches Replay_YYYY_MM_DD_HHMM.w3g format
  # 2. Fall back to earliest upload timestamp
  def played_at
    uploads = body&.dig("uploads") || []

    # First, try to parse date from filename (most accurate)
    if uploads.any?
      parsed_date = parse_date_from_filename(uploads)
      if parsed_date
        # Filename time is local timezone (no TZ info), so use whichever is
        # earliest between filename date and upload time. A match can't be
        # played after it was uploaded, and timezone offsets (e.g. Korean UTC+9)
        # can push the filename date into the future.
        upload_time = earliest_upload_at
        return upload_time && upload_time < parsed_date ? upload_time : parsed_date
      end
    end

    # Fall back to earliest upload timestamp
    earliest_upload_at
  end

  # Returns the earliest upload timestamp (when replay was first uploaded to wc3stats)
  def earliest_upload_at
    uploads = body&.dig("uploads") || []

    if uploads.any?
      earliest_timestamp = uploads.map { |u| u["timestamp"] }.compact.min
      return Time.at(earliest_timestamp) if earliest_timestamp
    end

    # Final fallback to playedOn timestamp (which is the latest upload)
    timestamp = body&.dig("playedOn")
    Time.at(timestamp) if timestamp
  end

  # Parse date from replay filename if it matches the standard format
  # Format: Replay_YYYY_MM_DD_HHMM.w3g (e.g., Replay_2025_10_19_1942.w3g)
  # Returns nil if filename is missing or doesn't match the format
  def parse_date_from_filename(uploads)
    uploads.each do |upload|
      filename = upload["filename"]
      next unless filename

      # Match format: Replay_YYYY_MM_DD_HHMM.w3g
      if filename =~ /\AReplay_(\d{4})_(\d{2})_(\d{2})_(\d{2})(\d{2})\.w3g\z/i
        year, month, day, hour, minute = $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i
        begin
          return Time.new(year, month, day, hour, minute, 0)
        rescue ArgumentError
          # Invalid date, try next upload
          next
        end
      end
    end
    nil
  end

  def replay_hash
    body&.dig("hash")
  end

  # Player data
  def players
    body&.dig("data", "game", "players") || []
  end

  def winners
    players.select { |p| p["isWinner"] == true }
  end

  def losers
    players.select { |p| p["isWinner"] == false }
  end

  # Determine if "good" team won based on replay data
  # Team 0 = Good (Forces of Middle Earth), Team 1 = Evil (Forces of Sauron)
  def good_victory?
    winners.any? { |p| p["team"] == 0 }
  end

  # Determine if the game ended in a draw (players typed -draw)
  def is_draw?
    players.any? { |p| p["flags"]&.include?("drawer") }
  end

  # Early leave detection (player left within first 3 minutes)
  EARLY_LEAVE_THRESHOLD = 180  # 3 minutes in seconds

  def has_early_leaver?
    early_leavers.any?
  end

  # Returns array of player data for players who left within first 3 minutes
  # Only the first leaver(s) count - others who left after get a pass
  def early_leavers
    # Exclude observers: isObserver flag, team 2, or players without winner/loser flags
    game_players = players.reject { |p|
      p["isObserver"] ||
        p["team"] == 2 ||
        (Array(p["flags"]) & [ "winner", "loser" ]).empty?
    }
    return [] if game_players.empty?

    # Find players who left early (within 180 seconds)
    players_with_early_leave = game_players.select { |p|
      p["leftAt"].present? && p["leftAt"] <= EARLY_LEAVE_THRESHOLD
    }
    return [] if players_with_early_leave.empty?

    # Only the first leaver(s) count as early leavers
    first_leave_time = players_with_early_leave.map { |p| p["leftAt"] }.min
    players_with_early_leave.select { |p| p["leftAt"] == first_leave_time }
  end

  # Returns battletags of early leavers
  def early_leaver_battletags
    early_leavers.map { |p| p["name"] }
  end

  def player_by_name(name)
    players.find { |p| p["name"] == name }
  end

  # Team data
  def team_players(team_number)
    players.select { |p| p["team"] == team_number }
  end

  # Statistics helpers
  def total_unit_kills_for_player(player_name)
    player = player_by_name(player_name)
    player&.dig("variables", "unitKills")
  end

  def total_hero_kills_for_player(player_name)
    player = player_by_name(player_name)
    player&.dig("variables", "heroKills")
  end

  def chatlog
    raw_chatlog = body&.dig("data", "chatlog") || []
    raw_chatlog.map do |msg|
      msg.merge(
        "message" => fix_encoding(msg["message"]),
        "playerName" => fix_encoding(msg["playerName"])
      )
    end
  end

  def events
    body&.dig("data", "game", "events") || []
  end

  def player_name_by_id(player_id)
    player = players.find { |p| p["id"] == player_id }
    player&.dig("name")&.split("#")&.first || "Player #{player_id}"
  end

  def fix_encoding(str)
    return str if str.nil? || str.empty?

    # The data was UTF-8 but got incorrectly decoded as Latin-1/CP1252
    # and then re-encoded to UTF-8 multiple times, causing multi-level encoding corruption.
    # We need to reverse this process, potentially multiple times.
    result = str
    max_iterations = 3

    max_iterations.times do
      begin
        # Try to decode: treat the string's bytes as if they were Latin-1 (ISO-8859-1),
        # then reinterpret those bytes as UTF-8.
        # Using Latin-1 because it maps bytes 0-255 directly to codepoints 0-255,
        # which allows us to recover the original byte sequence.
        fixed = result.encode("ISO-8859-1", "UTF-8").force_encoding("UTF-8")

        break unless fixed.valid_encoding? && fixed != result
        result = fixed
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        break
      end
    end

    result
  end
end
