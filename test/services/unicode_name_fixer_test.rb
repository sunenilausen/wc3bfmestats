require "test_helper"

class UnicodeNameFixerTest < ActiveSupport::TestCase
  setup do
    Appearance.destroy_all
    Match.destroy_all
    Player.destroy_all
    Wc3statsReplay.destroy_all
  end

  # Helper to create double-encoded mojibake (simulates how data gets corrupted)
  def create_mojibake(korean_text)
    # UTF-8 bytes interpreted as Latin-1, then re-encoded as UTF-8
    korean_text.encode("UTF-8").bytes.pack("C*").force_encoding("ISO-8859-1").encode("UTF-8")
  end

  test "fixes Korean mojibake in player nickname" do
    original_korean = "아멘"
    mojibake_name = create_mojibake(original_korean)

    player = Player.create!(
      nickname: mojibake_name,
      battletag: "#{mojibake_name}#1234",
      elo_rating: 1500
    )

    fixer = UnicodeNameFixer.new
    fixer.call

    player.reload
    assert_equal original_korean, player.nickname
    assert player.nickname.valid_encoding?
  end

  test "leaves valid ASCII names unchanged" do
    player = Player.create!(
      nickname: "NormalPlayer",
      battletag: "NormalPlayer#1234",
      elo_rating: 1500
    )

    fixer = UnicodeNameFixer.new
    fixer.call

    player.reload
    assert_equal "NormalPlayer", player.nickname
    assert_equal "NormalPlayer#1234", player.battletag
  end

  test "leaves valid Korean names unchanged" do
    player = Player.create!(
      nickname: "한글이름",
      battletag: "한글이름#1234",
      elo_rating: 1500
    )

    fixer = UnicodeNameFixer.new
    fixer.call

    player.reload
    assert_equal "한글이름", player.nickname
  end

  test "preview returns list of players to fix" do
    mojibake = create_mojibake("테스트")
    Player.create!(nickname: mojibake, battletag: "#{mojibake}#1234", elo_rating: 1500)
    Player.create!(nickname: "Normal", battletag: "Normal#5678", elo_rating: 1500)

    fixer = UnicodeNameFixer.new
    preview = fixer.preview

    assert_equal 1, preview.count
    assert_equal mojibake, preview.first[:nickname][:from]
    assert_equal "테스트", preview.first[:nickname][:to]
  end

  test "tracks fixed count" do
    Player.create!(nickname: create_mojibake("플레이어1"), battletag: "Test#1234", elo_rating: 1500)
    Player.create!(nickname: create_mojibake("플레이어2"), battletag: "Test2#5678", elo_rating: 1500)

    fixer = UnicodeNameFixer.new
    fixer.call

    assert_equal 2, fixer.fixed_count
  end

  test "fixes player names in replay body" do
    mojibake = create_mojibake("한글이름")
    replay = Wc3statsReplay.create!(
      wc3stats_replay_id: 12345,
      body: {
        "data" => {
          "game" => {
            "players" => [
              { "name" => "#{mojibake}#1234", "team" => 0 },
              { "name" => "Normal#5678", "team" => 1 }
            ]
          }
        }
      }
    )

    fixer = UnicodeNameFixer.new
    fixer.call

    replay.reload
    players = replay.body.dig("data", "game", "players")
    assert_equal "한글이름#1234", players[0]["name"]
    assert_equal "Normal#5678", players[1]["name"]
  end

  test "returns self for chaining" do
    fixer = UnicodeNameFixer.new
    result = fixer.call

    assert_equal fixer, result
  end
end
