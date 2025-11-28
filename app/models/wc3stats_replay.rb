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
  # Returns nil if not parseable
  def map_version
    return nil unless map_file_name

    # Match pattern like "BFME4.5e.w3x", "BFME4.5.w3x", or "BFME4.3gObs.w3x"
    if map_file_name =~ /BFME(\d+\.\d+[a-z]?(?:Obs)?)\.w3x/i
      $1
    end
  end

  def game_length
    body&.dig("length")
  end

  def played_at
    # Try to extract date from the file path (e.g., /data/replays/2025/11/18/hash.w3g)
    file_path = body&.dig("file") || body&.dig("uploads", 0, "file")
    if file_path && file_path =~ %r{/data/replays/(\d{4})/(\d{2})/(\d{2})/}
      Date.new($1.to_i, $2.to_i, $3.to_i)
    else
      # Fall back to playedOn timestamp
      timestamp = body&.dig("playedOn")
      Time.at(timestamp) if timestamp
    end
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
    body&.dig("data", "chatlog") || []
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
