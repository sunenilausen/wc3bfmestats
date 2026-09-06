require "test_helper"

class SuspiciousMatchFinderIdleTailTest < ActiveSupport::TestCase
  def build_replay(leave_times, winners:)
    Wc3statsReplay.create!(
      wc3stats_replay_id: 9001,
      body: {
        "length" => leave_times.max,
        "data" => { "game" => { "players" => leave_times.each_with_index.map { |left_at, slot|
          {
            "slot" => slot, "name" => "Player#{slot}", "team" => slot < 5 ? 0 : 1,
            "isWinner" => winners[slot], "leftAt" => left_at
          }
        } } }
      }
    )
  end

  def reasons_for(replay)
    match = Match.create!(wc3stats_replay: replay, good_victory: true, seconds: replay.effective_length)
    SuspiciousMatchFinder.new(scope: Match.where(id: match.id)).call.flat_map(&:reasons)
  end

  test "flags a match the straggler's team was handed" do
    replay = build_replay(
      [ 15159, 2591, 2470, 2264, 2255, 2676, 2666, 2664, 2657, 2656 ],
      winners: [ true ] * 5 + [ false ] * 5
    )

    reason = reasons_for(replay).find { |r| r.include?("after the game ended") }

    assert reason, "expected an idle tail reason"
    assert_includes reason, "Player0"
    assert_includes reason, "and the win went to their team"
    assert_includes reason, "contested 2676s"
  end

  test "still flags the match when the straggler lost" do
    replay = build_replay(
      [ 15159, 2591, 2470, 2264, 2255, 2676, 2666, 2664, 2657, 2656 ],
      winners: [ false ] * 5 + [ true ] * 5
    )

    reason = reasons_for(replay).find { |r| r.include?("after the game ended") }

    assert reason
    assert_not_includes reason, "and the win went to their team"
  end

  test "says nothing about an ordinary game" do
    replay = build_replay(
      [ 1000, 1000, 1000, 998, 995, 950, 948, 947, 945, 940 ],
      winners: [ true ] * 5 + [ false ] * 5
    )

    assert_empty reasons_for(replay).select { |r| r.include?("after the game ended") }
  end
end
