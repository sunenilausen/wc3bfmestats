require "test_helper"

class EloRecalculatorTest < ActiveSupport::TestCase
  setup do
    Appearance.destroy_all
    Match.destroy_all
    Player.destroy_all
    Faction.destroy_all

    # Create factions
    @gondor = Faction.create!(name: "Gondor", color: "red", good: true)
    @mordor = Faction.create!(name: "Mordor", color: "brown", good: false)

    # Create players with seed ratings
    @player1 = Player.create!(nickname: "Player1", battletag: "Player1#1234", elo_rating: 1500, elo_rating_seed: 1500)
    @player2 = Player.create!(nickname: "Player2", battletag: "Player2#5678", elo_rating: 1500, elo_rating_seed: 1500)
  end

  test "resets all player ratings to seed values" do
    # Modify player ratings from seed
    @player1.update!(elo_rating: 1700)
    @player2.update!(elo_rating: 1300)

    recalculator = EloRecalculator.new
    recalculator.call

    @player1.reload
    @player2.reload

    assert_equal 1500, @player1.elo_rating
    assert_equal 1500, @player2.elo_rating
  end

  test "processes matches in chronological order" do
    # Create two matches - player1 wins first, player2 wins second
    match1 = Match.create!(played_at: 1.day.ago, good_victory: true, seconds: 1800)
    match1.appearances.create!(player: @player1, faction: @gondor)
    match1.appearances.create!(player: @player2, faction: @mordor)

    match2 = Match.create!(played_at: Time.current, good_victory: false, seconds: 1800)
    match2.appearances.create!(player: @player1, faction: @gondor)
    match2.appearances.create!(player: @player2, faction: @mordor)

    recalculator = EloRecalculator.new
    recalculator.call

    assert_equal 2, recalculator.matches_processed

    # After match1: player1 wins (+16), player2 loses (-16) -> 1516, 1484
    # After match2: player1 loses (-15), player2 wins (+15) -> 1501, 1499
    # (slight asymmetry due to changed ratings)
    @player1.reload
    @player2.reload

    # Player1 won then lost, player2 lost then won
    # Should be close to 1500 but slightly different
    assert_in_delta 1500, @player1.elo_rating, 5
    assert_in_delta 1500, @player2.elo_rating, 5
  end

  test "clears appearance elo data before recalculating" do
    match = Match.create!(played_at: Time.current, good_victory: true, seconds: 1800)
    app1 = match.appearances.create!(player: @player1, faction: @gondor, elo_rating: 1600, elo_rating_change: 20)
    app2 = match.appearances.create!(player: @player2, faction: @mordor, elo_rating: 1400, elo_rating_change: -20)

    recalculator = EloRecalculator.new
    recalculator.call

    app1.reload
    app2.reload

    # Should have fresh calculations from seed rating
    assert_equal 1500, app1.elo_rating
    assert_equal 1500, app2.elo_rating
    assert_equal 16, app1.elo_rating_change
    assert_equal(-16, app2.elo_rating_change)
  end

  test "includes matches without played_at using created_at for ordering" do
    Match.create!(played_at: nil, good_victory: true, seconds: 1800)
    Match.create!(played_at: Time.current, good_victory: true, seconds: 1800)

    recalculator = EloRecalculator.new
    recalculator.call

    assert_equal 2, recalculator.matches_processed
  end

  test "uses default elo when seed is nil" do
    @player1.update!(elo_rating: 1700, elo_rating_seed: nil)

    recalculator = EloRecalculator.new
    recalculator.call

    @player1.reload
    assert_equal 1500, @player1.elo_rating
  end

  test "returns self for chaining" do
    recalculator = EloRecalculator.new
    result = recalculator.call

    assert_equal recalculator, result
  end
end
