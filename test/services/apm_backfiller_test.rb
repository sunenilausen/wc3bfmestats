require "test_helper"

class ApmBackfillerTest < ActiveSupport::TestCase
  test "updates appearances missing apm from replay data" do
    # Create a player and match with replay
    player = Player.create!(nickname: "Test", battletag: "Test#1234")
    replay = Wc3statsReplay.create!(
      wc3stats_replay_id: 999999,
      body: {
        "data" => {
          "game" => {
            "players" => [
              { "name" => "Test#1234", "apm" => 150, "slot" => 0, "isWinner" => true }
            ]
          }
        }
      }
    )
    match = Match.create!(
      wc3stats_replay: replay,
      uploaded_at: Time.current,
      seconds: 3600,
      good_victory: true
    )
    faction = factions(:gondor)
    appearance = Appearance.create!(
      match: match,
      player: player,
      faction: faction,
      hero_kills: 0,
      unit_kills: 100,
      apm: nil
    )

    backfiller = ApmBackfiller.new
    backfiller.call

    appearance.reload
    assert_equal 150, appearance.apm
    assert_equal 1, backfiller.updated_count
    assert_equal 0, backfiller.skipped_count
  end

  test "skips appearances that already have apm" do
    player = Player.create!(nickname: "Test2", battletag: "Test2#1234")
    replay = Wc3statsReplay.create!(
      wc3stats_replay_id: 999998,
      body: {
        "data" => {
          "game" => {
            "players" => [
              { "name" => "Test2#1234", "apm" => 200, "slot" => 0, "isWinner" => true }
            ]
          }
        }
      }
    )
    match = Match.create!(
      wc3stats_replay: replay,
      uploaded_at: Time.current,
      seconds: 3600,
      good_victory: true
    )
    faction = factions(:gondor)
    appearance = Appearance.create!(
      match: match,
      player: player,
      faction: faction,
      hero_kills: 0,
      unit_kills: 100,
      apm: 180  # Already has APM
    )

    backfiller = ApmBackfiller.new
    backfiller.call

    appearance.reload
    assert_equal 180, appearance.apm  # Should remain unchanged
    assert_equal 0, backfiller.updated_count
  end

  test "handles alternative battletags" do
    player = Player.create!(
      nickname: "AltTest",
      battletag: "AltTest#5678",
      alternative_battletags: ["OldTag#1234"]
    )
    replay = Wc3statsReplay.create!(
      wc3stats_replay_id: 999997,
      body: {
        "data" => {
          "game" => {
            "players" => [
              { "name" => "OldTag#1234", "apm" => 175, "slot" => 0, "isWinner" => true }
            ]
          }
        }
      }
    )
    match = Match.create!(
      wc3stats_replay: replay,
      uploaded_at: Time.current,
      seconds: 3600,
      good_victory: true
    )
    faction = factions(:gondor)
    appearance = Appearance.create!(
      match: match,
      player: player,
      faction: faction,
      hero_kills: 0,
      unit_kills: 100,
      apm: nil
    )

    backfiller = ApmBackfiller.new
    backfiller.call

    appearance.reload
    assert_equal 175, appearance.apm
    assert_equal 1, backfiller.updated_count
  end
end
