require "test_helper"

# One player sitting in a finished game inflates the recorded replay length,
# which lands in every "percentage of the game" derived from it - most
# damagingly stayPercent, which scales the winners' rating change.
class Wc3statsReplayIdleTailTest < ActiveSupport::TestCase
  # leave_times is slot 0..9, in slot order.
  def replay(leave_times, length: leave_times.max, winners: [ true ] * 5 + [ false ] * 5)
    Wc3statsReplay.new(
      wc3stats_replay_id: 1,
      body: {
        "length" => length,
        "data" => { "game" => { "players" => leave_times.each_with_index.map { |left_at, slot|
          {
            "slot" => slot,
            "name" => "Player#{slot}",
            "team" => slot < 5 ? 0 : 1,
            "isWinner" => winners[slot],
            "leftAt" => left_at,
            "stayPercent" => (left_at.to_f / length * 100).round(2)
          }
        } } }
      }
    )
  end

  # A normal game: the losers concede, the winners sit through the victory
  # screen a few seconds later.
  NORMAL = [ 1000, 1000, 1000, 998, 995, 950, 948, 947, 945, 940 ].freeze

  test "an ordinary game has no idle tail" do
    r = replay(NORMAL)

    assert_not r.idle_tail?
    assert_nil r.idle_tail_seconds
    assert_equal r.game_length, r.effective_length
    assert_empty r.idle_stragglers
  end

  test "the end-of-game leave cascade is not an idle tail" do
    # Everyone out within a minute of each other - the threshold sits well
    # above the widest real cascade in the data (65s).
    r = replay([ 1065, 1000, 998, 995, 990, 988, 985, 980, 975, 970 ])

    assert_not r.idle_tail?
  end

  test "one player idling is stripped back to the contested length" do
    r = replay([ 15159, 2591, 2470, 2264, 2255, 2676, 2666, 2664, 2657, 2656 ])

    assert r.idle_tail?
    assert_equal 2676, r.effective_length
    assert_equal 12483, r.idle_tail_seconds
    assert_equal [ "Player0" ], r.idle_stragglers.map { |p| p["name"] }
  end

  test "two players idling together do not hide each other" do
    r = replay([ 9000, 6000, 2000, 1990, 1985, 1980, 1975, 1970, 1965, 1960 ])

    assert_equal 2000, r.effective_length
    assert_equal [ "Player0", "Player1" ], r.idle_stragglers.map { |p| p["name"] }
  end

  test "a slow trickle never strips the game away" do
    # Every gap clears the threshold, but stripping past half the players
    # would leave no game to measure.
    r = replay([ 3000, 2800, 2600, 2400, 2200, 2000, 1800, 1600, 1400, 1200 ])

    assert_operator r.effective_length, :>=, 2000
    assert_operator r.idle_stragglers.size, :<=, 5
  end

  test "stay percent is measured against the contested game" do
    r = replay([ 15159, 2591, 2470, 2264, 2255, 2676, 2666, 2664, 2657, 2656 ])
    by_name = r.players.index_by { |p| p["name"] }

    # The replay's own stayPercent had the team mates at 15-17%.
    assert_in_delta 17.09, by_name["Player1"]["stayPercent"], 0.01
    assert_in_delta 96.82, r.stay_percent_for(by_name["Player1"]), 0.01

    # The straggler is capped rather than reported as 566%.
    assert_equal 100.0, r.stay_percent_for(by_name["Player0"])
  end

  test "stay percent is left alone when nobody idled" do
    r = replay(NORMAL)
    player = r.players.first

    assert_equal player["stayPercent"], r.stay_percent_for(player)
  end

  test "observers and empty slots are ignored" do
    r = replay(NORMAL)
    r.body["data"]["game"]["players"] << {
      "slot" => 10, "name" => "Watcher", "team" => 2, "isWinner" => nil, "leftAt" => 99_999
    }

    assert_not r.idle_tail?
    assert_equal r.game_length, r.effective_length
  end
end
