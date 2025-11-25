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
        played_at: wc3stats_replay.played_at,
        seconds: wc3stats_replay.game_length,
        good_victory: determine_good_victory
      )
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

        match.appearances.create!(
          player: player,
          faction: faction,
          hero_kills: player_data.dig("variables", "heroKills") || 0,
          unit_kills: player_data.dig("variables", "unitKills") || 0
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

    def find_or_create_player(player_data)
      battletag = player_data["name"]
      return nil if battletag.blank?

      player = Player.find_by(battletag: battletag)
      return player if player

      nickname = battletag.split("#").first
      Player.create!(
        battletag: battletag,
        nickname: nickname,
        elo_rating: 1500,
        elo_rating_seed: 1500
      )
    end

    def set_ignore_flags(match)
      appearances = match.appearances.reload

      # Ignore unit kills when unit_kills is 0
      appearances.each do |app|
        app.update_column(:ignore_unit_kills, true) if app.unit_kills == 0
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
