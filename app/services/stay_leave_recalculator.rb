# Recalculates stay/leave percentages for all players based on replay data
#
# A player is considered to have "left early" (a real leave) if:
# 1. They left before 90% of the game ended, AND
# 2. They were the first to leave (no one left before them), AND
# 3. No teammate left within 60 seconds after them
#
# stay_pct = percentage of games where player stayed or leave was excused
# leave_pct = percentage of games where player had a real early leave
#
class StayLeaveRecalculator
  # Minimum percentage of game that must be played to count as "stayed"
  STAY_THRESHOLD = 0.90

  # Grace period: if a teammate leaves within this many seconds, the leave is excused
  LEAVE_GRACE_PERIOD = 60

  attr_reader :players_updated, :errors

  def initialize
    @players_updated = 0
    @errors = []
    @player_stats = Hash.new { |h, k| h[k] = { stayed: 0, left: 0 } }
  end

  def call
    # Wrap in transaction so users can view the site with old data during recalculation
    ActiveRecord::Base.transaction do
      process_all_matches
      update_all_players
    end
    self
  end

  private

  def process_all_matches
    Match.includes(:wc3stats_replay, appearances: :player)
         .where(ignored: false)
         .find_each do |match|
      process_match(match)
    rescue StandardError => e
      @errors << "Match ##{match.id}: #{e.message}"
    end
  end

  def process_match(match)
    replay = match.wc3stats_replay
    return unless replay&.body

    game = replay.body.dig("data", "game")
    return unless game && game["players"]

    game_players = game["players"].reject { |p| p["isObserver"] }
    game_length = replay.game_length || match.seconds
    return unless game_length && game_length > 0

    # Get all players with leave times, sorted by leave time
    players_with_leave = game_players.select { |p| p["leftAt"].present? }
                                      .sort_by { |p| p["leftAt"] }

    return if players_with_leave.empty?

    # The effective end is the latest leave time
    effective_end = players_with_leave.last["leftAt"]
    threshold = effective_end * STAY_THRESHOLD

    # First leave time (to check if someone is first to leave)
    first_leave_time = players_with_leave.first["leftAt"]

    # Process each player in the match
    match.appearances.each do |appearance|
      player = appearance.player
      next unless player

      # Find this player's data in the replay
      player_data = find_player_in_replay(game_players, player, replay)
      next unless player_data

      left_at = player_data["leftAt"]
      next unless left_at

      # Check if player stayed (left at or after 90% of effective game end)
      if left_at >= threshold
        @player_stats[player.id][:stayed] += 1
        next
      end

      # Player left early - check if it's excused
      if is_excused_leave?(player_data, players_with_leave, first_leave_time)
        @player_stats[player.id][:stayed] += 1
      else
        @player_stats[player.id][:left] += 1
      end
    end
  end

  def is_excused_leave?(player_data, all_players_with_leave, first_leave_time)
    my_left_at = player_data["leftAt"]
    my_team = player_data["team"]

    # Excused if someone else left before them
    return true if my_left_at > first_leave_time

    # Excused if a teammate left within grace period after them
    teammates_after = all_players_with_leave.select do |p|
      p["team"] == my_team && p["leftAt"] > my_left_at
    end

    teammates_after.any? { |p| p["leftAt"] - my_left_at <= LEAVE_GRACE_PERIOD }
  end

  def find_player_in_replay(game_players, player, replay)
    game_players.find do |p|
      battletag = p["name"]
      next unless battletag
      fixed_battletag = replay.fix_encoding(battletag.gsub("\\", ""))
      player.battletag == fixed_battletag || player.battletag == battletag ||
        player.alternative_battletags&.include?(fixed_battletag) ||
        player.alternative_battletags&.include?(battletag)
    end
  end

  def update_all_players
    @player_stats.each do |player_id, stats|
      player = Player.find_by(id: player_id)
      next unless player

      total = stats[:stayed] + stats[:left]
      next if total == 0

      stay_pct = (stats[:stayed].to_f / total * 100).round(1)
      leave_pct = (stats[:left].to_f / total * 100).round(1)

      player.update!(
        stay_pct: stay_pct,
        leave_pct: leave_pct,
        games_stayed: stats[:stayed],
        games_left: stats[:left]
      )

      @players_updated += 1
    end
  end
end
