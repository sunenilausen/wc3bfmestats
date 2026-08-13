require "test_helper"

class PlayerFormTest < ActiveSupport::TestCase
  test "reads results from the player's point of view, most recent first" do
    match = matches(:one)
    match.update!(good_victory: true, is_draw: false, ignored: false)

    good = match.appearances.detect { |a| a.faction&.good? }
    evil = match.appearances.detect { |a| a.faction && !a.faction.good? }

    form = PlayerForm.recent([ good.player_id, evil.player_id ])

    assert_equal PlayerForm::WIN, form[good.player_id].first
    assert_equal PlayerForm::LOSS, form[evil.player_id].first
  end

  test "a draw counts as neither" do
    match = matches(:one)
    match.update!(good_victory: true, is_draw: true, ignored: false)
    appearance = match.appearances.detect(&:player_id)

    assert_equal PlayerForm::DRAW, PlayerForm.recent([ appearance.player_id ]).dig(appearance.player_id, 0)
  end

  test "keeps at most the requested number of games" do
    player_id = matches(:one).appearances.detect(&:player_id).player_id

    form = PlayerForm.recent([ player_id ], games: 1)

    assert_operator form[player_id].size, :<=, 1
  end

  test "no query for an empty player list" do
    assert_equal({}, PlayerForm.recent([]))
  end
end
