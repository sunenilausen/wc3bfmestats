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
end
