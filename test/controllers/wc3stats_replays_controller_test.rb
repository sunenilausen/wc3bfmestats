require "test_helper"

class Wc3statsReplaysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @wc3stats_replay = wc3stats_replays(:one)
  end

  test "should get index" do
    get wc3stats_replays_url
    assert_response :success
  end

  test "should get new" do
    get new_wc3stats_replay_url
    assert_response :success
  end

  test "should create wc3stats_replay" do
    assert_difference("Wc3statsReplay.count") do
      post wc3stats_replays_url, params: { wc3stats_replay: { body: @wc3stats_replay.body, wc3stats_replay_id: 999 } }
    end

    assert_redirected_to wc3stats_replay_url(Wc3statsReplay.last)
  end

  test "should show wc3stats_replay" do
    get wc3stats_replay_url(@wc3stats_replay)
    assert_response :success
  end

  test "should get edit" do
    get edit_wc3stats_replay_url(@wc3stats_replay)
    assert_response :success
  end

  test "should update wc3stats_replay" do
    patch wc3stats_replay_url(@wc3stats_replay), params: { wc3stats_replay: { body: @wc3stats_replay.body, wc3stats_replay_id: @wc3stats_replay.wc3stats_replay_id } }
    assert_redirected_to wc3stats_replay_url(@wc3stats_replay)
  end

  test "should destroy wc3stats_replay" do
    assert_difference("Wc3statsReplay.count", -1) do
      delete wc3stats_replay_url(@wc3stats_replay)
    end

    assert_redirected_to wc3stats_replays_url
  end
end
