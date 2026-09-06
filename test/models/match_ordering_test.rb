require "test_helper"

# The bug this guards against: 43% of replays have no parseable filename, so
# their played_at is really an upload time. A bulk upload of old replays put
# 4.4e games at the top of the site, ahead of games actually played that week.
class MatchOrderingTest < ActiveSupport::TestCase
  setup do
    Appearance.delete_all
    Match.delete_all

    @old_version_bulk_uploaded = Match.create!(
      map_version: "4.4e",
      played_at: Time.zone.parse("2026-08-20"),   # the upload date, not the game
      uploaded_at: Time.zone.parse("2026-08-20")
    )
    @old_version_played_then = Match.create!(
      map_version: "4.4e",
      played_at: Time.zone.parse("2025-03-13"),
      uploaded_at: Time.zone.parse("2025-03-13")
    )
    @current_version = Match.create!(
      map_version: "4.7RC2",
      played_at: Time.zone.parse("2026-08-17"),
      uploaded_at: Time.zone.parse("2026-08-17")
    )
  end

  test "map version leads, so a late upload of an old version stays in its era" do
    assert_equal [ @old_version_played_then, @old_version_bulk_uploaded, @current_version ],
      Match.chronological.to_a
  end

  test "reverse_chronological is the exact inverse" do
    assert_equal Match.chronological.to_a.reverse, Match.reverse_chronological.to_a
  end

  test "played_at still orders matches within a version" do
    assert Match.chronological.to_a.index(@old_version_played_then) <
      Match.chronological.to_a.index(@old_version_bulk_uploaded)
  end

  test "the rank is assigned on save and follows the version" do
    assert_equal MapVersionOrder.rank("4.4e"), @old_version_played_then.map_version_order

    @old_version_played_then.update!(map_version: "4.6c")
    assert_equal MapVersionOrder.rank("4.6c"), @old_version_played_then.map_version_order
  end

  test "with_map_version_order fills the rank in for update_columns writers" do
    match = @current_version
    changes = Match.with_map_version_order(match, { map_version: "4.5e" })
    assert_equal MapVersionOrder.rank("4.5e"), changes[:map_version_order]

    assert_equal({ uploaded_at: nil }, Match.with_map_version_order(match, { uploaded_at: nil }))
  end
end
