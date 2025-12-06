module Wc3stats
  class MatchBuilder
    # Map slot positions to faction names
    SLOT_TO_FACTION = {
      0 => "Gondor",
      1 => "Rohan",
      2 => "Dol Amroth",
      3 => "Fellowship",
      4 => "Fangorn",
      5 => "Isengard",
      6 => "Easterlings",
      7 => "Harad",
      8 => "Minas Morgul",
      9 => "Mordor"
    }.freeze

    attr_reader :wc3stats_replay, :errors

    def initialize(wc3stats_replay)
      @wc3stats_replay = wc3stats_replay
      @errors = []
    end

    def call
      return false unless valid_replay?
      return wc3stats_replay.match if wc3stats_replay.match.present?

      build_match
    end

    private

    def valid_replay?
      if wc3stats_replay.nil?
        @errors << "No replay provided"
        return false
      end

      if wc3stats_replay.players.empty?
        @errors << "Replay has no players"
        return false
      end

      true
    end

    def build_match
      ActiveRecord::Base.transaction do
        match = create_match
        create_appearances(match)
        create_observers
        set_ignore_flags(match)
        match
      end
    rescue ActiveRecord::RecordInvalid => e
      @errors << "Failed to create match: #{e.message}"
      false
    end

    def create_match
      Match.create!(
        wc3stats_replay: wc3stats_replay,
        uploaded_at: wc3stats_replay.played_at,
        seconds: wc3stats_replay.game_length,
        good_victory: determine_good_victory,
        major_version: wc3stats_replay.major_version,
        build_version: wc3stats_replay.build_version,
        map_version: wc3stats_replay.map_version,
        ignored: should_ignore_match?
      )
    end

    # Minimum game length in seconds (2 minutes)
    MIN_GAME_LENGTH = 120

    def should_ignore_match?
      wc3stats_replay.test_map? ||
        wc3stats_replay.incomplete_game? ||
        too_short?
    end

    def too_short?
      game_length = wc3stats_replay.game_length
      game_length.present? && game_length < MIN_GAME_LENGTH
    end

    def determine_good_victory
      # Team 0 is Good, Team 1 is Evil
      # Check if any team 0 player won
      good_players = active_players.select { |p| p["team"] == 0 }
      good_players.any? { |p| p["isWinner"] == true }
    end

    def create_appearances(match)
      active_players.each do |player_data|
        slot = player_data["slot"]
        faction_name = SLOT_TO_FACTION[slot]
        next unless faction_name

        faction = Faction.find_by(name: faction_name)
        next unless faction

        player = find_or_create_player(player_data)
        next unless player

        self_heal = player_data.dig("variables", "selfHeal")
        team_heal = player_data.dig("variables", "teamHeal")
        total_heal = (self_heal || 0) + (team_heal || 0) if self_heal || team_heal

        match.appearances.create!(
          player: player,
          faction: faction,
          hero_kills: player_data.dig("variables", "heroKills") || 0,
          unit_kills: player_data.dig("variables", "unitKills") || 0,
          castles_razed: player_data.dig("variables", "castlesRazed"),
          self_heal: self_heal,
          team_heal: team_heal,
          total_heal: total_heal
        )
      end
    end

    def active_players
      # Only include players in slots 0-9 (actual game players, not observers)
      # and who have a definitive win/loss status
      @active_players ||= wc3stats_replay.players.select do |p|
        slot = p["slot"]
        slot.present? && slot >= 0 && slot <= 9 && !p["isWinner"].nil?
      end
    end

    def observer_players
      # Players who are observers (not in slots 0-9 or without win/loss status)
      @observer_players ||= wc3stats_replay.players.select do |p|
        slot = p["slot"]
        slot.nil? || slot > 9 || p["isWinner"].nil?
      end
    end

    def create_observers
      observer_players.each do |player_data|
        find_or_create_player(player_data)
      end
    end

    def find_or_create_player(player_data)
      battletag = player_data["name"]
      return nil if battletag.blank?

      # Fix unicode encoding issues (e.g., Korean names)
      fixed_battletag = fix_encoding(battletag)

      # Try to find by battletag (including alternative_battletags for merged players)
      player = Player.find_by_any_battletag(fixed_battletag) || Player.find_by_any_battletag(battletag)
      return player if player

      nickname = fixed_battletag.split("#").first
      Player.create!(
        battletag: fixed_battletag,
        nickname: nickname,
        custom_rating: NewPlayerDefaults::CUSTOM_RATING,
        ml_score: NewPlayerDefaults::ML_SCORE
      )
    end

    def fix_encoding(str)
      return str if str.nil? || str.empty?

      begin
        # Reverse double-encoded UTF-8: decode UTF-8 to bytes via Latin-1, then interpret as UTF-8
        bytes = str.encode("ISO-8859-1", "UTF-8").bytes
        fixed = bytes.pack("C*").force_encoding("UTF-8")

        # Only use fixed version if valid and different
        if fixed.valid_encoding? && fixed != str && printable?(fixed)
          fixed
        else
          str
        end
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        str
      end
    end

    def printable?(str)
      return false unless str.valid_encoding?
      printable_count = str.chars.count { |c| c.match?(/[[:print:]]/) }
      printable_count > str.length / 2
    end

    def set_ignore_flags(match)
      appearances = match.appearances.reload

      # Ignore unit kills when unit_kills is 0
      appearances.each do |app|
        app.update_column(:ignore_unit_kills, true) if app.unit_kills == 0
        app.update_column(:ignore_hero_kills, true) if app.unit_kills == 0
      end

      # Ignore hero kills when all players in the match have 0 hero kills
      all_zero_hero_kills = appearances.all? { |a| a.hero_kills.nil? || a.hero_kills == 0 }
      if all_zero_hero_kills
        appearances.each do |app|
          app.update_column(:ignore_hero_kills, true)
        end
      end
    end
  end
end
