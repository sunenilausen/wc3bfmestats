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
end
