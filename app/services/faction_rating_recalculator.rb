# Calculates faction-specific ratings for each player-faction combination
# Simple approach: Faction rating = CR * modifier based on win rate and games played
#
# - Best faction ≈ CR (or slightly above if win rate is high)
# - Bad factions < CR (based on how poorly you perform)
# - Unplayed factions << CR (unproven)
class FactionRatingRecalculator
  # Minimum games to be considered "proven" on a faction
  MIN_GAMES_FOR_CONFIDENCE = 10

  # How much win rate can affect rating (above/below CR)
  # 70% win rate with enough games = CR * 1.10 (10% boost)
  # 30% win rate with enough games = CR * 0.90 (10% penalty)
  MAX_WIN_RATE_MODIFIER = 0.15

  # Penalty for unproven factions (scales down as games increase)
  # 0 games = 10% below CR, approaches 0% penalty at MIN_GAMES_FOR_CONFIDENCE
  UNPROVEN_PENALTY = 0.10

  attr_reader :errors

  def initialize
    @errors = []
  end

  def call
    calculate_all_faction_ratings
    self
  end

  private

  def calculate_all_faction_ratings
    # Preload player CRs
    player_crs = Player.pluck(:id, :custom_rating).to_h

    PlayerFactionStat.find_each do |stat|
      player_cr = player_crs[stat.player_id]
      next unless player_cr

      faction_rating = calculate_faction_rating(player_cr, stat.games_played, stat.wins)
      stat.update_column(:faction_rating, faction_rating.round(1))
    rescue StandardError => e
      @errors << "PlayerFactionStat ##{stat.id}: #{e.message}"
    end
  end

  def calculate_faction_rating(cr, games, wins)
    return cr * (1 - UNPROVEN_PENALTY) if games == 0

    win_rate = wins.to_f / games

    # Calculate confidence (0 to 1) based on games played
    confidence = [games.to_f / MIN_GAMES_FOR_CONFIDENCE, 1.0].min

    # Win rate modifier: how much above/below 50% win rate
    # 50% = no modifier, 70% = +0.15, 30% = -0.15 (at full confidence)
    win_rate_deviation = (win_rate - 0.5) * 2  # -1 to +1
    win_rate_modifier = win_rate_deviation * MAX_WIN_RATE_MODIFIER * confidence

    # Unproven penalty: reduces as games increase
    unproven_penalty = UNPROVEN_PENALTY * (1 - confidence)

    # Final modifier combines win rate effect and unproven penalty
    total_modifier = 1 + win_rate_modifier - unproven_penalty

    cr * total_modifier
  end
end
