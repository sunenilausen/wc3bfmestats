require "test_helper"

class RatingAdjustmentTest < ActiveSupport::TestCase
  test "a veteran on their usual faction with a neutral weight has nothing to show" do
    breakdown = RatingAdjustment.for(
      cr: 1500, games: 100, faction_games: 20, ml_score: 0, faction_name: "Rohan"
    )

    assert_equal 0, breakdown.total.round
    assert_not breakdown.any?
    assert_equal 1500.0, breakdown.weighted_cr
  end

  test "new player performing below average is penalised" do
    breakdown = RatingAdjustment.for(
      cr: 1300, games: 0, faction_games: 0, ml_score: -20, faction_name: "Rohan"
    )

    assert_equal(-80, breakdown.new_player.round)
    assert breakdown.any?
  end

  test "new player performing at or above average keeps their rating" do
    breakdown = RatingAdjustment.for(
      cr: 1300, games: 0, faction_games: 0, ml_score: 5, faction_name: "Rohan"
    )

    assert_equal 0.0, breakdown.new_player
  end

  test "the new player penalty fades as games are played" do
    half_way = RatingAdjustment.for(
      cr: 1300, games: 15, faction_games: 15, ml_score: -20, faction_name: "Rohan"
    )
    debut = RatingAdjustment.for(
      cr: 1300, games: 0, faction_games: 0, ml_score: -20, faction_name: "Rohan"
    )

    assert_in_delta debut.new_player / 2, half_way.new_player, 0.01
  end

  test "an unplayed faction costs the full familiarity penalty" do
    breakdown = RatingAdjustment.for(
      cr: 1500, games: 100, faction_games: 0, ml_score: 0, faction_name: "Rohan"
    )

    assert_equal(-LobbyWinPredictor::MAX_FACTION_FAMILIARITY_PENALTY, breakdown.familiarity.round)
    assert_equal(-LobbyWinPredictor::MAX_FACTION_FAMILIARITY_PENALTY, breakdown.total.round)
  end

  test "faction impact weight scales what is left after the penalties" do
    breakdown = RatingAdjustment.for(
      cr: 1500, games: 100, faction_games: 20, ml_score: 0, faction_name: "Mordor"
    )

    assert_equal 1.08, breakdown.faction_weight
    assert_in_delta 1500 * 0.08, breakdown.faction, 0.01
    assert_in_delta 1500 * 1.08, breakdown.weighted_cr, 0.01
  end

  test "the parts add up to the total" do
    breakdown = RatingAdjustment.for(
      cr: 1400, games: 10, faction_games: 0, ml_score: -15, faction_name: "Mordor"
    )

    assert_in_delta breakdown.new_player + breakdown.familiarity + breakdown.faction,
      breakdown.total, 0.0001
    assert_in_delta breakdown.cr + breakdown.total, breakdown.weighted_cr, 0.0001
  end

  test "an unknown faction is treated as neutral" do
    assert_equal LobbyWinPredictor::DEFAULT_FACTION_WEIGHT, RatingAdjustment.faction_weight(nil)
    assert_equal LobbyWinPredictor::DEFAULT_FACTION_WEIGHT, RatingAdjustment.faction_weight("Not A Faction")
  end
end
