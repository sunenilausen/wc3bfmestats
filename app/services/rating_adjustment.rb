# How a player's Custom Rating is adjusted before it counts toward their team's
# prediction score:
#
#   1. a penalty while they are new and performing below average (see
#      LobbyWinPredictor for why this exists),
#   2. a penalty for playing a faction they rarely touch, and
#   3. the faction's impact weight, which scales whatever is left.
#
# The maths lives here so the lobby prediction, the stored match prediction and
# the display of both can never drift apart. Only the final weighted CR feeds a
# prediction - the breakdown exists so a player can see where their number came
# from.
class RatingAdjustment
  Breakdown = Struct.new(:cr, :new_player, :familiarity, :faction_weight, keyword_init: true) do
    # CR once the new-player and familiarity penalties are applied
    def effective_cr
      cr + new_player + familiarity
    end

    # What this player is actually worth to their team's average
    def weighted_cr
      effective_cr * faction_weight
    end

    # The faction impact weight, expressed in CR points
    def faction
      weighted_cr - effective_cr
    end

    # Every adjustment together, as one delta from the raw CR
    def total
      weighted_cr - cr
    end

    # Whether there is anything worth showing (a rounded delta of 0 is noise)
    def any?
      total.round != 0
    end
  end

  # Build the breakdown from the raw inputs. Every caller has these to hand:
  # a lobby reads them off the player, a finished match reads them off the
  # snapshot frozen onto the appearance.
  def self.for(cr:, games:, faction_games:, ml_score:, faction_name: nil)
    Breakdown.new(
      cr: cr.to_f,
      new_player: new_player_adjustment(cr, games, ml_score),
      familiarity: familiarity_adjustment(games, faction_games),
      faction_weight: faction_weight(faction_name)
    )
  end

  # Penalty for a player who has not played enough games for their CR to be
  # trusted and whose performance so far is below average. Never a bonus: a new
  # player performing well is simply worth their CR.
  def self.new_player_adjustment(cr, games, ml_score)
    games = games.to_i
    ml_score = ml_score.to_f
    return 0.0 if games >= LobbyWinPredictor::GAMES_FOR_FULL_CR_TRUST
    return 0.0 if ml_score >= LobbyWinPredictor::ML_BASELINE

    ml_deviation = ml_score - LobbyWinPredictor::ML_BASELINE
    remaining_doubt = 1.0 - (games / LobbyWinPredictor::GAMES_FOR_FULL_CR_TRUST.to_f)

    (ml_deviation / 50.0) * LobbyWinPredictor::MAX_ML_CR_ADJUSTMENT * remaining_doubt
  end

  # CR once the new-player penalty is applied
  def self.effective_cr(cr, games, ml_score)
    cr.to_f + new_player_adjustment(cr, games, ml_score)
  end

  # Penalty for playing a faction the player rarely picks, relative to how
  # often they play any faction.
  def self.familiarity_adjustment(games, faction_games)
    -(LobbyWinPredictor.unfamiliarity_ratio(games, faction_games) *
      LobbyWinPredictor::MAX_FACTION_FAMILIARITY_PENALTY)
  end

  def self.faction_weight(faction_name)
    LobbyWinPredictor::FACTION_IMPACT_WEIGHTS[faction_name] || LobbyWinPredictor::DEFAULT_FACTION_WEIGHT
  end
end
