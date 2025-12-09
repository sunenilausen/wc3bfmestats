# frozen_string_literal: true

# Finds matches that may have incorrect victory data
# by analyzing kill statistics, chat messages, base deaths, and upsets
class SuspiciousMatchFinder
  # Thresholds for suspicion
  UNIT_KILL_RATIO_THRESHOLD = 1.5    # Losing team has 50%+ more unit kills
  HERO_KILL_RATIO_THRESHOLD = 1.5    # Losing team has 50%+ more hero kills
  FORFEIT_PATTERNS = %w[-ff -gg -forfeit -quit -leave].freeze

  # Time window at end of game to consider as "cascade" deaths (in seconds)
  END_GAME_CASCADE_WINDOW = 60

  # Upset thresholds - when underdog wins with very low predicted chance
  MAJOR_UPSET_THRESHOLD = 25.0   # Team with <25% chance won - very suspicious
  MODERATE_UPSET_THRESHOLD = 35.0 # Team with <35% chance won - somewhat suspicious

  Result = Struct.new(:match, :reasons, keyword_init: true)

  def initialize(scope: Match.where(ignored: false))
    @scope = scope
  end

  def call
    suspicious_matches = []

    @scope.includes(:appearances, :wc3stats_replay).find_each do |match|
      reasons = analyze_match(match)
      suspicious_matches << Result.new(match: match, reasons: reasons) if reasons.any?
    end

    suspicious_matches.sort_by { |r| -r.reasons.size }
  end

  private

  def analyze_match(match)
    reasons = []

    reasons.concat(check_kill_disparity(match))
    reasons.concat(check_forfeit_messages(match))
    reasons.concat(check_base_deaths(match))
    reasons.concat(check_upset(match))

    reasons
  end

  def check_kill_disparity(match)
    reasons = []

    winning_team = match.good_victory ? :good : :evil
    losing_team = match.good_victory ? :evil : :good

    winning_appearances = match.appearances.select { |a| a.faction.good == (winning_team == :good) }
    losing_appearances = match.appearances.select { |a| a.faction.good == (losing_team == :good) }

    winning_unit_kills = winning_appearances.sum(&:unit_kills)
    losing_unit_kills = losing_appearances.sum(&:unit_kills)

    winning_hero_kills = winning_appearances.sum(&:hero_kills)
    losing_hero_kills = losing_appearances.sum(&:hero_kills)

    # Check unit kill disparity
    if winning_unit_kills > 0 && losing_unit_kills > 0
      if losing_unit_kills > winning_unit_kills * UNIT_KILL_RATIO_THRESHOLD
        ratio = (losing_unit_kills.to_f / winning_unit_kills).round(1)
        reasons << "Losing team had #{ratio}x more unit kills (#{losing_unit_kills} vs #{winning_unit_kills})"
      end
    end

    # Check hero kill disparity
    if winning_hero_kills > 0 && losing_hero_kills > 0
      if losing_hero_kills > winning_hero_kills * HERO_KILL_RATIO_THRESHOLD
        ratio = (losing_hero_kills.to_f / winning_hero_kills).round(1)
        reasons << "Losing team had #{ratio}x more hero kills (#{losing_hero_kills} vs #{winning_hero_kills})"
      end
    end

    reasons
  end

  def check_forfeit_messages(match)
    reasons = []
    replay = match.wc3stats_replay
    return reasons unless replay

    chatlog = replay.chatlog
    return reasons if chatlog.empty?

    winning_team_id = match.good_victory ? 0 : 1
    players = replay.players

    # Map player IDs to team
    player_teams = players.each_with_object({}) do |player, hash|
      hash[player["id"]] = player["team"]
    end

    # Find forfeit messages from winning team players
    forfeit_messages = chatlog.select do |msg|
      message_text = msg["message"]&.downcase || ""
      player_id = msg["playerId"]
      player_team = player_teams[player_id]

      # Check if winning team player sent a forfeit message
      player_team == winning_team_id && FORFEIT_PATTERNS.any? { |pattern| message_text.include?(pattern) }
    end

    if forfeit_messages.any?
      count = forfeit_messages.size
      player_names = forfeit_messages.map { |msg| replay.player_name_by_id(msg["playerId"]) }.uniq
      reasons << "#{count} forfeit message(s) from winning team (#{player_names.join(', ')})"
    end

    reasons
  end

  def check_base_deaths(match)
    reasons = []
    replay = match.wc3stats_replay
    return reasons unless replay

    game_length = replay.game_length
    return reasons unless game_length

    base_events = replay.events.select { |e| e["eventName"] == "baseDestroyed" }
    return reasons if base_events.empty?

    # Filter out cascade deaths at end of game
    # These are bases that die within the last X seconds, likely due to game ending
    cascade_cutoff = game_length - END_GAME_CASCADE_WINDOW
    meaningful_base_deaths = base_events.select { |e| e["time"] < cascade_cutoff }

    # Count base deaths per team
    good_bases_lost = 0
    evil_bases_lost = 0

    meaningful_base_deaths.each do |event|
      base_name = event["args"]&.first&.gsub("\\", "")
      next unless base_name

      faction_name = Faction::BASE_TO_FACTION[base_name]
      next unless faction_name

      faction = Faction.find_by(name: faction_name)
      next unless faction

      if faction.good?
        good_bases_lost += 1
      else
        evil_bases_lost += 1
      end
    end

    # Check if winning team lost more bases (suspicious)
    if match.good_victory && good_bases_lost > evil_bases_lost && good_bases_lost > 0
      reasons << "Winning team (Good) lost more bases before game end (#{good_bases_lost} vs #{evil_bases_lost})"
    elsif !match.good_victory && evil_bases_lost > good_bases_lost && evil_bases_lost > 0
      reasons << "Winning team (Evil) lost more bases before game end (#{evil_bases_lost} vs #{good_bases_lost})"
    end

    reasons
  end

  def check_upset(match)
    reasons = []

    # Use stored prediction from CR+ system
    predicted_good_pct = match.predicted_good_win_pct
    return reasons unless predicted_good_pct

    predicted_evil_pct = 100.0 - predicted_good_pct

    # Determine which team was the underdog and if they won
    if match.good_victory
      # Good won - check if they were the underdog
      winning_team_pct = predicted_good_pct
      winning_team = "Good"
    else
      # Evil won - check if they were the underdog
      winning_team_pct = predicted_evil_pct
      winning_team = "Evil"
    end

    # Flag major upsets (underdog with <25% chance won)
    if winning_team_pct < MAJOR_UPSET_THRESHOLD
      reasons << "Major upset: #{winning_team} won with only #{winning_team_pct.round(1)}% predicted chance"
    elsif winning_team_pct < MODERATE_UPSET_THRESHOLD
      reasons << "Upset: #{winning_team} won with #{winning_team_pct.round(1)}% predicted chance"
    end

    reasons
  end
end
