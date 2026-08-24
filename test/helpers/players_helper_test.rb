require "test_helper"

class PlayersHelperTest < ActionView::TestCase
  include PlayersHelper

  test "no flag icon for an unflagged player" do
    assert_equal "", player_flag_icon(players(:one))
  end

  test "no flag icon for a missing player" do
    assert_equal "", player_flag_icon(nil)
  end

  test "flag icon carries the note as its tooltip" do
    player = players(:one)
    player.update!(flagged: true, flag_note: "Feeds heroes")

    html = player_flag_icon(player)

    assert_includes html, "🚩"
    assert_includes html, 'title="Feeds heroes"'
  end

  test "flag icon falls back to generic text without a note" do
    player = players(:one)
    player.update!(flagged: true)

    assert_includes player_flag_icon(player), 'title="Flagged by an admin"'
  end

  test "flag note is escaped into the tooltip" do
    player = players(:one)
    player.update!(flagged: true, flag_note: %(Says "gg" <script>))

    html = player_flag_icon(player)

    assert_not_includes html, "<script>"
    assert_includes html, "&quot;gg&quot;"
  end
end
