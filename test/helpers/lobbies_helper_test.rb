require "test_helper"

class LobbiesHelperTest < ActionView::TestCase
  include LobbiesHelper

  test "an under-observed player is marked with their unrated games" do
    player = players(:one)
    player.update!(custom_rating_games_played: 7, unrated_games: 20)

    assert_match(/\+20u/, unrated_games_marker(player))
  end

  test "an established player is not marked, however much is missing" do
    player = players(:one)
    player.update!(custom_rating_games_played: 561, unrated_games: 443)

    assert_equal "", unrated_games_marker(player),
      "the marker exists to qualify a NEW badge - an established player does not carry one"
  end

  test "nothing is shown when there is nothing missing" do
    player = players(:one)
    player.update!(custom_rating_games_played: 3, unrated_games: 0)

    assert_equal "", unrated_games_marker(player)
  end

  test "an empty slot has no marker" do
    assert_equal "", unrated_games_marker(nil)
  end

  test "the threshold matches the one the NEW badge uses" do
    assert_equal 30, LobbiesHelper::UNRATED_GAMES_SHOWN_BELOW
  end
end
