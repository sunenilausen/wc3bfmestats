require "test_helper"

class Wc3statsReplaysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @wc3stats_replay = wc3stats_replays(:one)
    @admin = users(:admin)
  end

  test "should get index" do
    get wc3stats_replays_url
    assert_response :success
  end

  test "should get new as admin" do
    sign_in @admin
    get new_wc3stats_replay_url
    assert_response :success
  end

  test "should redirect new when not admin" do
    get new_wc3stats_replay_url
    assert_redirected_to root_path
  end

  test "should create wc3stats_replay as admin" do
    sign_in @admin
    assert_difference("Wc3statsReplay.count") do
      post wc3stats_replays_url, params: { wc3stats_replay: { body: @wc3stats_replay.body, wc3stats_replay_id: 999 } }
    end

    assert_redirected_to wc3stats_replay_url(Wc3statsReplay.last)
  end

  test "should not create wc3stats_replay when not admin" do
    assert_no_difference("Wc3statsReplay.count") do
      post wc3stats_replays_url, params: { wc3stats_replay: { body: @wc3stats_replay.body, wc3stats_replay_id: 999 } }
    end

    assert_redirected_to root_path
  end

  test "should show wc3stats_replay" do
    get wc3stats_replay_url(@wc3stats_replay)
    assert_response :success
  end

  test "should get edit as admin" do
    sign_in @admin
    get edit_wc3stats_replay_url(@wc3stats_replay)
    assert_response :success
  end

  test "should redirect edit when not admin" do
    get edit_wc3stats_replay_url(@wc3stats_replay)
    assert_redirected_to root_path
  end

  test "should update wc3stats_replay as admin" do
    sign_in @admin
    patch wc3stats_replay_url(@wc3stats_replay), params: { wc3stats_replay: { body: @wc3stats_replay.body, wc3stats_replay_id: @wc3stats_replay.wc3stats_replay_id } }
    assert_redirected_to wc3stats_replay_url(@wc3stats_replay)
  end

  test "should not update wc3stats_replay when not admin" do
    patch wc3stats_replay_url(@wc3stats_replay), params: { wc3stats_replay: { wc3stats_replay_id: 123 } }
    assert_redirected_to root_path
  end

  test "should destroy wc3stats_replay as admin" do
    sign_in @admin
    assert_difference("Wc3statsReplay.count", -1) do
      delete wc3stats_replay_url(@wc3stats_replay)
    end

    assert_redirected_to wc3stats_replays_url
  end

  test "should not destroy wc3stats_replay when not admin" do
    assert_no_difference("Wc3statsReplay.count") do
      delete wc3stats_replay_url(@wc3stats_replay)
    end

    assert_redirected_to root_path
  end
end
