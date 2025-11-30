require "test_helper"

class PlayersCsvExporterTest < ActiveSupport::TestCase
  setup do
    @player = players(:one)
  end

  test "generates CSV with headers" do
    csv = PlayersCsvExporter.call
    lines = csv.split("\n")

    assert_includes lines.first, "nickname"
    assert_includes lines.first, "battletag"
    assert_includes lines.first, "custom_rating"
    assert_includes lines.first, "ml_score"
    assert_includes lines.first, "matches"
    assert_includes lines.first, "last_appearance"
    assert_includes lines.first, "wins"
    assert_includes lines.first, "losses"
    assert_includes lines.first, "win_rate"
  end

  test "includes player data in CSV" do
    csv = PlayersCsvExporter.call

    assert_includes csv, @player.nickname
    assert_includes csv, @player.battletag
  end

  test "orders players by custom_rating descending" do
    csv = PlayersCsvExporter.call
    lines = csv.split("\n")

    # Skip header row, get player rows
    data_lines = lines[1..]

    # Extract custom ratings from CSV
    custom_ratings = data_lines.map do |line|
      parts = CSV.parse_line(line)
      parts[2].to_i  # custom_rating is 3rd column
    end

    assert_equal custom_ratings.sort.reverse, custom_ratings, "Players should be sorted by custom_rating descending"
  end

  test "calculates win rate correctly" do
    csv = PlayersCsvExporter.call

    # Player one has matches in fixtures, check win rate format
    assert_match(/\d+(\.\d+)?%/, csv, "CSV should contain win rate percentages")
  end

  test "handles player with no matches" do
    # Create a player with no appearances
    player = Player.create!(
      nickname: "NewPlayer",
      battletag: "NewPlayer#9999",
      custom_rating: 1300,
      ml_score: 35.0
    )

    csv = PlayersCsvExporter.call

    assert_includes csv, "NewPlayer"
    assert_includes csv, "N/A"  # No last appearance
    assert_includes csv, "0%"   # 0% win rate
  end

  test "class method call works" do
    csv = PlayersCsvExporter.call

    assert csv.is_a?(String)
    assert csv.present?
  end
end
