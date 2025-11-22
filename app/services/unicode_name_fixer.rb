class UnicodeNameFixer
  # Detect double-encoded UTF-8 (UTF-8 interpreted as Latin-1, then re-encoded as UTF-8)
  # Korean characters when double-encoded produce sequences like:
  # ì (U+00EC), í (U+00ED), ë (U+00EB), etc. followed by control characters (U+0080-U+009F)
  # or characters in the Latin-1 supplement range (U+00A0-U+00FF)
  MOJIBAKE_INDICATORS = [
    /[ìíîïëêè][\u0080-\u00BF]/, # Korean lead bytes as Latin-1 chars followed by continuation
    /Ã[¡-¿]/,                    # Another common double-encoding pattern
    /[\u00C0-\u00EF][\u0080-\u00BF]{1,2}/ # Generic double-encoded multi-byte pattern
  ].freeze

  attr_reader :fixed_count, :errors, :changes

  def initialize
    @fixed_count = 0
    @errors = []
    @changes = []
  end

  def call
    fix_player_names
    fix_replay_player_names
    self
  end

  def preview
    players_to_fix = []

    Player.find_each do |player|
      fixed_nickname = fix_encoding(player.nickname)
      fixed_battletag = fix_encoding(player.battletag)

      if fixed_nickname != player.nickname || fixed_battletag != player.battletag
        players_to_fix << {
          id: player.id,
          nickname: { from: player.nickname, to: fixed_nickname },
          battletag: { from: player.battletag, to: fixed_battletag }
        }
      end
    end

    players_to_fix
  end

  private

  def fix_player_names
    Player.find_each do |player|
      fixed_nickname = fix_encoding(player.nickname)
      fixed_battletag = fix_encoding(player.battletag)

      if fixed_nickname != player.nickname || fixed_battletag != player.battletag
        @changes << {
          type: :player,
          id: player.id,
          nickname: { from: player.nickname, to: fixed_nickname },
          battletag: { from: player.battletag, to: fixed_battletag }
        }

        player.update!(nickname: fixed_nickname, battletag: fixed_battletag)
        @fixed_count += 1
      end
    rescue StandardError => e
      @errors << "Player ##{player.id}: #{e.message}"
    end
  end

  def fix_replay_player_names
    Wc3statsReplay.find_each do |replay|
      next unless replay.body.is_a?(Hash)

      players = replay.body.dig("data", "game", "players")
      next unless players.is_a?(Array)

      changed = false
      players.each do |player_data|
        next unless player_data.is_a?(Hash)

        original_name = player_data["name"]
        next unless original_name

        fixed_name = fix_encoding(original_name)
        if fixed_name != original_name
          player_data["name"] = fixed_name
          changed = true
        end
      end

      if changed
        replay.update!(body: replay.body)
        @changes << { type: :replay, id: replay.id }
      end
    rescue StandardError => e
      @errors << "Replay ##{replay.id}: #{e.message}"
    end
  end

  def fix_encoding(str)
    return str if str.nil? || str.empty?

    # Try to fix double-encoded UTF-8
    # The string was: UTF-8 bytes → interpreted as Latin-1 → re-encoded as UTF-8
    # To reverse: decode UTF-8 to chars → get byte values → interpret as UTF-8
    begin
      # Get the bytes by encoding to Latin-1 (this reverses the second encoding step)
      bytes = str.encode("ISO-8859-1", "UTF-8").bytes
      # Interpret those bytes as UTF-8
      fixed = bytes.pack("C*").force_encoding("UTF-8")

      # Only use the fixed version if it's valid UTF-8 and different
      if fixed.valid_encoding? && fixed != str && looks_like_valid_text?(fixed)
        fixed
      else
        str
      end
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      str
    end
  end

  def looks_like_valid_text?(str)
    # Check if the string looks like valid text (contains actual characters, not control chars)
    return false unless str.valid_encoding?

    # Should contain printable characters and not be mostly control characters
    printable_count = str.chars.count { |c| c.match?(/[[:print:]]/) }
    printable_count > str.length / 2
  end
end
