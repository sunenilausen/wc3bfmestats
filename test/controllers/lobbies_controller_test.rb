require "test_helper"

class LobbiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @lobby = lobbies(:one)
  end

  test "should get index" do
    get lobbies_url
    assert_response :success
  end

  test "should get new" do
    get new_lobby_url
    # New lobby now instantly creates and redirects to edit
    assert_redirected_to edit_lobby_url(Lobby.last)
  end

  test "should create lobby" do
    assert_difference("Lobby.count") do
      post lobbies_url, params: { lobby: {} }
    end

    assert_redirected_to lobby_url(Lobby.last)
  end

  test "should show lobby" do
    get lobby_url(@lobby)
    assert_response :success
  end

  test "should get edit" do
    # First create a lobby via the new action to get session ownership
    get new_lobby_url
    owned_lobby = Lobby.last
    get edit_lobby_url(owned_lobby)
    assert_response :success
  end

  test "should update lobby" do
    # First create a lobby via the new action to get session ownership
    get new_lobby_url
    owned_lobby = Lobby.last
    patch lobby_url(owned_lobby), params: { lobby: {} }
    # Update now redirects back to edit for auto-save workflow
    assert_redirected_to edit_lobby_url(owned_lobby)
  end

  test "should not allow editing lobby created by another session" do
    get edit_lobby_url(@lobby)
    assert_redirected_to lobby_url(@lobby)
  end

  test "should copy lobby" do
    assert_difference("Lobby.count") do
      post copy_lobby_url(@lobby)
    end

    new_lobby = Lobby.last
    assert_redirected_to edit_lobby_url(new_lobby)

    # Verify players were copied
    assert_equal @lobby.lobby_players.count, new_lobby.lobby_players.count
    @lobby.lobby_players.each do |original_lp|
      copied_lp = new_lobby.lobby_players.find_by(faction_id: original_lp.faction_id)
      assert_not_nil copied_lp
      assert_equal original_lp.player_id, copied_lp.player_id
    end
  end
end
