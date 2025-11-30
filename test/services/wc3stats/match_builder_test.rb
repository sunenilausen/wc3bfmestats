require "test_helper"

module Wc3stats
  class MatchBuilderTest < ActiveSupport::TestCase
    setup do
      # Clear existing data to isolate tests
      Appearance.destroy_all
      Match.destroy_all
      Player.destroy_all
      Wc3statsReplay.destroy_all

      @replay = Wc3statsReplay.create!(
        wc3stats_replay_id: 12345,
        body: {
          "name" => "Test Game",
          "map" => "BFME",
          "length" => 1800,
          "playedOn" => Time.current.to_i,
          "data" => {
            "game" => {
              "players" => [
                {
                  "name" => "GoodPlayer1#1234",
                  "slot" => 0,
                  "team" => 0,
                  "isWinner" => true,
                  "variables" => { "unitKills" => 100, "heroKills" => 5 }
                },
                {
                  "name" => "GoodPlayer2#5678",
                  "slot" => 1,
                  "team" => 0,
                  "isWinner" => true,
                  "variables" => { "unitKills" => 80, "heroKills" => 3 }
                },
                {
                  "name" => "EvilPlayer1#9999",
                  "slot" => 5,
                  "team" => 1,
                  "isWinner" => false,
                  "variables" => { "unitKills" => 60, "heroKills" => 2 }
                },
                {
                  "name" => "EvilPlayer2#1111",
                  "slot" => 6,
                  "team" => 1,
                  "isWinner" => false,
                  "variables" => { "unitKills" => 40, "heroKills" => 1 }
                }
              ]
            }
          }
        }
      )
    end

    test "creates match from replay data" do
      builder = MatchBuilder.new(@replay)
      match = builder.call

      assert match.is_a?(Match)
      assert_equal @replay, match.wc3stats_replay
      assert_equal 1800, match.seconds
      assert match.good_victory
    end

    test "creates players from replay data" do
      builder = MatchBuilder.new(@replay)
      builder.call

      assert_equal 4, Player.count
      assert Player.exists?(battletag: "GoodPlayer1#1234")
      assert Player.exists?(battletag: "EvilPlayer1#9999")
    end

    test "creates appearances with correct factions" do
      builder = MatchBuilder.new(@replay)
      match = builder.call

      assert_equal 4, match.appearances.count

      good_player = Player.find_by(battletag: "GoodPlayer1#1234")
      appearance = match.appearances.find_by(player: good_player)
      assert_equal "Gondor", appearance.faction.name
      assert_equal 100, appearance.unit_kills
      assert_equal 5, appearance.hero_kills

      evil_player = Player.find_by(battletag: "EvilPlayer1#9999")
      appearance = match.appearances.find_by(player: evil_player)
      assert_equal "Isengard", appearance.faction.name
    end

    test "sets good_victory to false when evil team wins" do
      @replay.update!(body: @replay.body.deep_merge({
        "data" => {
          "game" => {
            "players" => [
              { "name" => "GoodPlayer1#1234", "slot" => 0, "team" => 0, "isWinner" => false, "variables" => {} },
              { "name" => "EvilPlayer1#9999", "slot" => 5, "team" => 1, "isWinner" => true, "variables" => {} }
            ]
          }
        }
      }))

      builder = MatchBuilder.new(@replay)
      match = builder.call

      assert_not match.good_victory
    end

    test "reuses existing players" do
      existing_player = Player.create!(
        battletag: "GoodPlayer1#1234",
        nickname: "GoodPlayer1",
        custom_rating: 1400,
        ml_score: 45.0
      )

      builder = MatchBuilder.new(@replay)
      match = builder.call

      assert_equal 4, Player.count
      appearance = match.appearances.find_by(player: existing_player)
      assert_not_nil appearance
    end

    test "returns existing match if already created" do
      builder1 = MatchBuilder.new(@replay)
      match1 = builder1.call

      builder2 = MatchBuilder.new(@replay)
      match2 = builder2.call

      assert_equal match1.id, match2.id
      assert_equal 1, Match.count
    end

    test "returns false with errors for nil replay" do
      builder = MatchBuilder.new(nil)
      result = builder.call

      assert_equal false, result
      assert_includes builder.errors, "No replay provided"
    end

    test "returns false with errors for replay with no players" do
      empty_replay = Wc3statsReplay.create!(
        wc3stats_replay_id: 99999,
        body: { "data" => { "game" => { "players" => [] } } }
      )

      builder = MatchBuilder.new(empty_replay)
      result = builder.call

      assert_equal false, result
      assert_includes builder.errors, "Replay has no players"
    end

    test "creates players for observers but not appearances" do
      @replay.update!(body: @replay.body.deep_merge({
        "data" => {
          "game" => {
            "players" => [
              { "name" => "ActivePlayer#1234", "slot" => 0, "team" => 0, "isWinner" => true, "variables" => {} },
              { "name" => "Observer#5678", "slot" => 10, "team" => 2, "isWinner" => nil, "variables" => {} }
            ]
          }
        }
      }))

      builder = MatchBuilder.new(@replay)
      match = builder.call

      # Only active players get appearances
      assert_equal 1, match.appearances.count
      assert Player.exists?(battletag: "ActivePlayer#1234")
      # Observers are now created as players (but without appearances)
      assert Player.exists?(battletag: "Observer#5678")
    end
  end
end
