require "test_helper"

class PlayerFlagTest < ActiveSupport::TestCase
  setup do
    @player = players(:one)
  end

  test "stamps flagged_at when a player is flagged" do
    freeze_time do
      @player.update!(flagged: true, flag_note: "Feeds heroes")

      assert @player.flagged?
      assert_equal Time.current, @player.flagged_at
    end
  end

  test "keeps the original flagged_at when the note is edited" do
    @player.update!(flagged: true, flag_note: "Feeds heroes")
    first_flagged_at = @player.flagged_at

    travel 1.day do
      @player.update!(flag_note: "Feeds heroes and rage quits")
    end

    assert_equal first_flagged_at, @player.reload.flagged_at
  end

  test "clears flagged_at and the note when unflagged" do
    @player.update!(flagged: true, flag_note: "Feeds heroes")
    @player.update!(flagged: false)

    assert_nil @player.flagged_at
    assert_nil @player.flag_note
  end

  test "blank notes are stored as nil and fall back to generic text" do
    @player.update!(flagged: true, flag_note: "   ")

    assert_nil @player.flag_note
    assert_equal "Flagged by an admin", @player.flag_reason
  end

  test "flag_reason is the note when one is set" do
    @player.update!(flagged: true, flag_note: "Feeds heroes")

    assert_equal "Feeds heroes", @player.flag_reason
  end

  test "flagged scope only returns flagged players" do
    @player.update!(flagged: true)

    assert_includes Player.flagged, @player
    assert_equal [ @player ], Player.flagged.to_a
  end

  test "flagging moves the moderation cache key" do
    before = StatsCacheKey.moderation_key
    @player.update!(flagged: true, flag_note: "Feeds heroes")

    assert_not_equal before, StatsCacheKey.moderation_key
  end

  test "editing the note moves the moderation cache key" do
    @player.update!(flagged: true, flag_note: "Feeds heroes")
    before = StatsCacheKey.moderation_key
    @player.update!(flag_note: "Feeds heroes and rage quits")

    assert_not_equal before, StatsCacheKey.moderation_key
  end

  test "an unrelated player edit leaves the moderation cache key alone" do
    @player.update!(flagged: true, flag_note: "Feeds heroes")
    before = StatsCacheKey.moderation_key
    players(:two).update!(nickname: "Renamed")

    assert_equal before, StatsCacheKey.moderation_key
  end
end
