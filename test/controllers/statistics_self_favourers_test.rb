require "test_helper"

class StatisticsSelfFavourersTest < ActionDispatch::IntegrationTest
  # Builds a match hosted by `host`, with `host` playing on the given side and
  # the lobby predicted at `good_pct` for Good.
  def host_a_match(host:, good_pct:, host_good: true, host_plays: true)
    replay = Wc3statsReplay.create!(wc3stats_replay_id: rand(1_000_000), body: { "hash" => SecureRandom.hex(8) })
    match = Match.create!(ignored: false, good_victory: true, predicted_good_win_pct: good_pct,
                          host_battletag: host.battletag, wc3stats_replay: replay)
    if host_plays
      match.appearances.create!(player: host, faction: host_good ? factions(:gondor) : factions(:mordor))
    else
      match.appearances.create!(player: players(:two), faction: factions(:gondor))
    end
    match
  end

  setup do
    Match.destroy_all
    @host = players(:one)
    @host.update!(battletag: "TheHost#1")
  end

  def rows
    get statistics_url(map_version: "")
    assert_response :success
    controller.view_assigns["top_self_favourers"]
  end

  test "counts a host who put themselves on the favoured side" do
    host_a_match(host: @host, good_pct: 70.0, host_good: true)

    entry = rows.find { |r| r[:player].id == @host.id }
    assert_equal 1, entry[:favoured]
    assert_equal 1, entry[:played]
  end

  test "reads the prediction from the host's own side" do
    host_a_match(host: @host, good_pct: 70.0, host_good: false)

    entry = rows.find { |r| r[:player].id == @host.id }
    assert_nil entry, "70% for Good makes an Evil host the underdog, not a self-favourer"
  end

  test "a lobby the host sat out of does not count" do
    host_a_match(host: @host, good_pct: 90.0, host_plays: false)

    assert_empty rows, "hosting a game you do not play says nothing about favouring yourself"
  end

  test "balanced lobbies count as played but favour nobody" do
    host_a_match(host: @host, good_pct: 70.0)
    host_a_match(host: @host, good_pct: 50.0)

    entry = rows.find { |r| r[:player].id == @host.id }
    assert_equal 2, entry[:played]
    assert_equal 1, entry[:favoured]
    assert_equal 50.0, entry[:favoured_pct]
  end

  test "the underdog column is counted from the host's side too" do
    host_a_match(host: @host, good_pct: 70.0)
    host_a_match(host: @host, good_pct: 20.0)

    entry = rows.find { |r| r[:player].id == @host.id }
    assert_equal 1, entry[:favoured]
    assert_equal 1, entry[:underdog]
  end

  test "a host who never favoured themselves is left off the list" do
    host_a_match(host: @host, good_pct: 20.0)

    assert_empty rows
  end

  test "ranked by how many times, not by rate" do
    other = Player.create!(nickname: "Rare", battletag: "Rare#2")
    3.times { host_a_match(host: @host, good_pct: 70.0) }
    2.times { host_a_match(host: @host, good_pct: 50.0) }
    host_a_match(host: other, good_pct: 70.0)

    assert_equal [ @host.id, other.id ], rows.map { |r| r[:player].id },
      "3 of 5 outranks 1 of 1"
  end
end
