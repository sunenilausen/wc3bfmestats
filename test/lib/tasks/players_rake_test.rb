require "test_helper"
require "rake"

class PlayersRakeTest < ActiveSupport::TestCase
  def setup
    # Clear existing data in correct order due to foreign key constraints
    Appearance.destroy_all
    Match.destroy_all
    Player.destroy_all
    Wc3statsReplay.destroy_all

    # Load all rake tasks
    Rails.application.load_tasks

    # Clear any previously invoked state
    Rake::Task["players:generate"].reenable if Rake::Task.task_defined?("players:generate")
  end

  def teardown
    # Clean up after test
    Appearance.destroy_all
    Match.destroy_all
    Player.destroy_all
    Wc3statsReplay.destroy_all
  end

  test "generate task creates players from replay data" do
    Rake::Task["players:generate"].reenable
    # Create test replay data with players
    test_id = rand(100000..999999)
    replay1 = Wc3statsReplay.create!(
      wc3stats_replay_id: test_id,
      body: {
        "name" => "Test Game 1",
        "map" => "BFME Test Map",
        "length" => 1800,
        "playedOn" => Time.current.to_i,
        "data" => {
          "game" => {
            "players" => [
              {
                "name" => "Player1#1234",
                "team" => 1,
                "isWinner" => true,
                "variables" => {
                  "unitKills" => 100,
                  "heroKills" => 5
                }
              },
              {
                "name" => "Player2#5678",
                "team" => 2,
                "isWinner" => false,
                "variables" => {
                  "unitKills" => 80,
                  "heroKills" => 3
                }
              }
            ]
          }
        }
      }
    )

    replay2 = Wc3statsReplay.create!(
      wc3stats_replay_id: test_id + 1,
      body: {
        "name" => "Test Game 2",
        "map" => "BFME Test Map",
        "length" => 2100,
        "playedOn" => Time.current.to_i,
        "data" => {
          "game" => {
            "players" => [
              {
                "name" => "Player1#1234",
                "team" => 2,
                "isWinner" => false,
                "variables" => {
                  "unitKills" => 120,
                  "heroKills" => 4
                }
              },
              {
                "name" => "Player3",
                "team" => 1,
                "isWinner" => true,
                "variables" => {
                  "unitKills" => 150,
                  "heroKills" => 7
                }
              }
            ]
          }
        }
      }
    )

    # Capture output
    output = capture_output do
      Rake::Task["players:generate"].invoke
    end

    # Verify players were created
    assert_equal 3, Player.count, "Should create 3 unique players"

    # Check Player1 was created correctly
    player1 = Player.find_by(battletag: "Player1#1234")
    assert_not_nil player1
    assert_equal "Player1", player1.nickname
    assert_equal 1300, player1.custom_rating
    assert_equal(-15.0, player1.ml_score)

    # Check Player2 was created correctly
    player2 = Player.find_by(battletag: "Player2#5678")
    assert_not_nil player2
    assert_equal "Player2", player2.nickname

    # Check Player3 was created correctly (no battletag number)
    player3 = Player.find_by(battletag: "Player3")
    assert_not_nil player3
    assert_equal "Player3", player3.nickname

    # Verify output contains expected information
    output_string = output[0]
    assert_match /Found 3 unique players/, output_string
    assert_match /Successfully created: 3 players/, output_string
    assert_match /Player1#1234/, output_string
    assert_match /Games: 2, W\/L: 1\/1/, output_string
  end

  test "generate task handles empty replay database" do
    Rake::Task["players:generate"].reenable
    # Ensure no replays exist
    Wc3statsReplay.destroy_all

    output = capture_output do
      Rake::Task["players:generate"].invoke
    end

    output_string = output[0]
    assert_match /No replays found/, output_string
    assert_equal 0, Player.count
  end

  test "generate task skips existing players" do
    Rake::Task["players:generate"].reenable
    # Create an existing player
    existing_player = Player.create!(
      battletag: "ExistingPlayer#9999",
      nickname: "ExistingPlayer",
      custom_rating: 1400,
      ml_score: 45.0
    )

    # Create replay with both existing and new players
    replay = Wc3statsReplay.create!(
      wc3stats_replay_id: rand(100000..999999),
      body: {
        "name" => "Test Game 3",
        "map" => "BFME Test Map",
        "length" => 1500,
        "playedOn" => Time.current.to_i,
        "data" => {
          "game" => {
            "players" => [
              {
                "name" => "ExistingPlayer#9999",
                "team" => 1,
                "isWinner" => true,
                "variables" => {
                  "unitKills" => 200,
                  "heroKills" => 10
                }
              },
              {
                "name" => "NewPlayer#1111",
                "team" => 2,
                "isWinner" => false,
                "variables" => {
                  "unitKills" => 150,
                  "heroKills" => 5
                }
              }
            ]
          }
        }
      }
    )

    output = capture_output do
      Rake::Task["players:generate"].invoke
    end

    # Should only create 1 new player
    assert_equal 2, Player.count
    assert Player.exists?(battletag: "NewPlayer#1111")

    # Existing player should remain unchanged
    existing_player.reload
    assert_equal 1400, existing_player.custom_rating

    output_string = output[0]
    assert_match /Already in database: 1/, output_string
    assert_match /New players to create: 1/, output_string
  end

  test "generate task handles players with no battletag number" do
    Rake::Task["players:generate"].reenable
    replay = Wc3statsReplay.create!(
      wc3stats_replay_id: rand(100000..999999),
      body: {
        "name" => "Test Game 4",
        "map" => "BFME Test Map",
        "length" => 1200,
        "playedOn" => Time.current.to_i,
        "data" => {
          "game" => {
            "players" => [
              {
                "name" => "SimpleNickname",
                "team" => 1,
                "isWinner" => true,
                "variables" => {
                  "unitKills" => 90,
                  "heroKills" => 2
                }
              }
            ]
          }
        }
      }
    )

    capture_output do
      Rake::Task["players:generate"].invoke
    end

    player = Player.find_by(battletag: "SimpleNickname")
    assert_not_nil player
    assert_equal "SimpleNickname", player.nickname
    assert_equal "SimpleNickname", player.battletag
  end

  test "generate task calculates correct statistics" do
    Rake::Task["players:generate"].reenable
    # Create replays with known statistics
    test_id = rand(100000..999999)
    replay1 = Wc3statsReplay.create!(
      wc3stats_replay_id: test_id,
      body: {
        "name" => "Stats Game 1",
        "map" => "BFME Test Map",
        "length" => 1800,
        "playedOn" => Time.current.to_i,
        "data" => {
          "game" => {
            "players" => [
              {
                "name" => "StatsPlayer#1234",
                "team" => 1,
                "isWinner" => true,
                "variables" => {
                  "unitKills" => 100,
                  "heroKills" => 5
                }
              }
            ]
          }
        }
      }
    )

    replay2 = Wc3statsReplay.create!(
      wc3stats_replay_id: test_id + 1,
      body: {
        "name" => "Stats Game 2",
        "map" => "BFME Test Map",
        "length" => 2100,
        "playedOn" => Time.current.to_i,
        "data" => {
          "game" => {
            "players" => [
              {
                "name" => "StatsPlayer#1234",
                "team" => 1,
                "isWinner" => true,
                "variables" => {
                  "unitKills" => 200,
                  "heroKills" => 10
                }
              }
            ]
          }
        }
      }
    )

    replay3 = Wc3statsReplay.create!(
      wc3stats_replay_id: test_id + 2,
      body: {
        "name" => "Stats Game 3",
        "map" => "BFME Test Map",
        "length" => 1500,
        "playedOn" => Time.current.to_i,
        "data" => {
          "game" => {
            "players" => [
              {
                "name" => "StatsPlayer#1234",
                "team" => 2,
                "isWinner" => false,
                "variables" => {
                  "unitKills" => 50,
                  "heroKills" => 2
                }
              }
            ]
          }
        }
      }
    )

    output = capture_output do
      Rake::Task["players:generate"].invoke
    end

    output_string = output[0]

    # Player should have 3 games, 2 wins, 1 loss (66.7% win rate)
    assert_match /StatsPlayer#1234/, output_string
    assert_match /Games: 3, W\/L: 2\/1 \(66.7%\)/, output_string
    # Total kills: 350 units, 17 heroes
    assert_match /Kills: 350 units, 17 heroes/, output_string
  end

  private

  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    output = $stdout.string
    $stdout = original_stdout
    [ output ]
  end
end
