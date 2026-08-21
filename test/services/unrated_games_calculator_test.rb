require "test_helper"

class UnratedGamesCalculatorTest < ActiveSupport::TestCase
  # A replay whose map never reported a result: every player has isWinner nil,
  # so MatchBuilder builds the match with no appearances at all.
  def build_dropped_match(battletags, length: 900, map: "BFME4.5e.w3x")
    replay = Wc3statsReplay.create!(
      wc3stats_replay_id: rand(1_000_000),
      body: {
        "length" => length,
        "data" => { "game" => { "map" => "Maps/#{map}", "events" => [],
                                "players" => [] } }
      }
    )
    replay.body["data"]["game"]["players"] = battletags.each_with_index.map do |tag, i|
      { "name" => tag, "slot" => i, "team" => i < 5 ? 0 : 1, "isWinner" => nil }
    end
    replay.save!
    Match.create!(wc3stats_replay: replay, seconds: length, ignored: true)
    replay
  end

  test "counts the dropped games a player took part in" do
    player = players(:one)
    build_dropped_match([ player.battletag, "other#1" ])
    build_dropped_match([ player.battletag ])

    UnratedGamesCalculator.new.call

    assert_equal 2, player.reload.unrated_games
  end

  test "a merged player is credited once, not twice" do
    player = players(:one)
    player.update!(alternative_battletags: [ "OldName#9" ])
    build_dropped_match([ "OldName#9" ])

    UnratedGamesCalculator.new.call

    assert_equal 1, player.reload.unrated_games,
      "an alternative battletag is the same person, not a second total"
  end

  test "observers and out-of-range slots are not counted" do
    player = players(:one)
    replay = build_dropped_match([ "someone#1" ])
    replay.body["data"]["game"]["players"] << { "name" => player.battletag, "slot" => 12, "isWinner" => nil }
    replay.save!

    UnratedGamesCalculator.new.call

    assert_equal 0, player.reload.unrated_games, "slot 12 is an observer, not a player"
  end

  test "lobby-length games and test maps do not count" do
    player = players(:one)
    build_dropped_match([ player.battletag ], length: 60)
    build_dropped_match([ player.battletag ], map: "BFME4.5eTest.w3x")

    UnratedGamesCalculator.new.call

    assert_equal 0, player.reload.unrated_games
  end

  test "a rated game is not an unrated game" do
    player = players(:one)

    UnratedGamesCalculator.new.call

    assert_equal 0, player.reload.unrated_games,
      "the fixture match has appearances, so it was rated"
  end

  test "counts are replaced, not accumulated, when it runs again" do
    player = players(:one)
    build_dropped_match([ player.battletag ])

    UnratedGamesCalculator.new.call
    UnratedGamesCalculator.new.call

    assert_equal 1, player.reload.unrated_games
  end

  test "a player whose count drops back to zero is cleared" do
    player = players(:one)
    player.update!(unrated_games: 7)

    UnratedGamesCalculator.new.call

    assert_equal 0, player.reload.unrated_games
  end
end
