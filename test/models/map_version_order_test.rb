require "test_helper"

class MapVersionOrderTest < ActiveSupport::TestCase
  def assert_ordered(*versions)
    ranks = versions.map { |v| MapVersionOrder.rank(v) }
    assert_equal ranks.sort, ranks,
      "expected #{versions.inspect} to rank in that order, got #{versions.zip(ranks).inspect}"
  end

  test "orders by major then minor" do
    assert_ordered "3.9f", "4.0f", "4.1d", "4.7RC"
  end

  test "the plain release comes before its lettered patches" do
    assert_ordered "4.5", "4.5b", "4.5c", "4.5d", "4.5e"
  end

  test "a lettered patch never reaches the next minor" do
    assert_ordered "4.5e", "4.6"
  end

  test "pre-releases come before the release they lead up to" do
    assert_ordered "4.7RC", "4.7RC2", "4.7"
    assert_ordered "3.8Beta3", "3.8"
    assert_ordered "4.0jTest", "4.0jTest2", "4.0j"
  end

  test "Obs builds rank as the version they observe" do
    assert_equal MapVersionOrder.rank("4.4"), MapVersionOrder.rank("4.4Obs")
    assert_equal MapVersionOrder.rank("4.3g"), MapVersionOrder.rank("4.3gObs")
    assert_ordered "4.4Obs", "4.4b"
  end

  test "letter case does not matter" do
    assert_equal MapVersionOrder.rank("4.0l"), MapVersionOrder.rank("4.0L")
  end

  test "the duplicate-download suffix does not matter" do
    assert_equal MapVersionOrder.rank("4.1Test3"), MapVersionOrder.rank("4.1Test3~1")
  end

  test "returns nil for a version it cannot read" do
    assert_nil MapVersionOrder.rank(nil)
    assert_nil MapVersionOrder.rank("")
    assert_nil MapVersionOrder.rank("GFINALFOREVERDONE")
  end

  test "a match with no readable version borrows the rank of its era" do
    Appearance.delete_all
    Match.delete_all
    Match.create!(map_version: "4.5e", played_at: Time.zone.parse("2025-11-01"))
    Match.create!(map_version: "4.6c", played_at: Time.zone.parse("2026-01-01"))

    assert_equal MapVersionOrder.rank("4.5e"),
      MapVersionOrder.rank_for(nil, played_at: Time.zone.parse("2025-12-01"))
    assert_equal MapVersionOrder.rank("4.6c"),
      MapVersionOrder.rank_for(nil, played_at: Time.zone.parse("2026-02-01"))
  end

  test "a match older than every known version gets no rank" do
    Appearance.delete_all
    Match.delete_all
    Match.create!(map_version: "4.5e", played_at: Time.zone.parse("2025-11-01"))

    assert_nil MapVersionOrder.rank_for(nil, played_at: Time.zone.parse("2019-01-01"))
    assert_nil MapVersionOrder.rank_for(nil, played_at: nil)
  end
end
