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

  test "should save new player in lobby slot" do
    # Create a lobby with session ownership
    get new_lobby_url
    owned_lobby = Lobby.last

    faction = factions(:gondor)

    # Update the lobby to set a slot as "new player"
    patch lobby_url(owned_lobby), params: {
      lobby: {
        lobby_players_attributes: {
          "0" => {
            faction_id: faction.id,
            player_id: "",
            is_new_player: "1"
          }
        }
      }
    }

    assert_redirected_to edit_lobby_url(owned_lobby)

    # Verify the new player flag was saved
    owned_lobby.reload
    lp = owned_lobby.lobby_players.find_by(faction_id: faction.id)
    assert lp.is_new_player?, "Expected lobby player to be marked as new player"
    assert_nil lp.player_id, "Expected player_id to be nil for new player"
  end

  test "should persist new player after page refresh" do
    # Create a lobby with session ownership
    get new_lobby_url
    owned_lobby = Lobby.last

    faction = factions(:mordor)

    # Set a slot as "new player"
    patch lobby_url(owned_lobby), params: {
      lobby: {
        lobby_players_attributes: {
          "0" => {
            faction_id: faction.id,
            player_id: "",
            is_new_player: "1"
          }
        }
      }
    }

    # Simulate page refresh - get the edit page again
    get edit_lobby_url(owned_lobby)
    assert_response :success

    # Check the lobby still has the new player
    owned_lobby.reload
    lp = owned_lobby.lobby_players.find_by(faction_id: faction.id)
    assert lp.is_new_player?, "New player should persist after page refresh"
  end

  test "should copy lobby with new player" do
    # Create a lobby with a new player slot
    get new_lobby_url
    owned_lobby = Lobby.last

    faction = factions(:harad)

    # Set a slot as "new player"
    patch lobby_url(owned_lobby), params: {
      lobby: {
        lobby_players_attributes: {
          "0" => {
            faction_id: faction.id,
            player_id: "",
            is_new_player: "1"
          }
        }
      }
    }

    # Copy the lobby
    assert_difference("Lobby.count") do
      post copy_lobby_url(owned_lobby)
    end

    new_lobby = Lobby.last

    # Verify the new player was copied
    copied_lp = new_lobby.lobby_players.find_by(faction_id: faction.id)
    assert_not_nil copied_lp
    assert copied_lp.is_new_player?, "New player flag should be copied"
    assert_nil copied_lp.player_id
  end

  test "should get prediction endpoint" do
    get new_lobby_url
    owned_lobby = Lobby.last

    get prediction_lobby_url(owned_lobby), as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert json.key?("prediction")
    assert json.key?("player_details")
  end

  test "prediction should include new player in calculation" do
    get new_lobby_url
    owned_lobby = Lobby.last

    faction = factions(:gondor)

    # Set a slot as "new player"
    patch lobby_url(owned_lobby), params: {
      lobby: {
        lobby_players_attributes: {
          "0" => {
            faction_id: faction.id,
            player_id: "",
            is_new_player: "1"
          }
        }
      }
    }

    # Get prediction
    get prediction_lobby_url(owned_lobby), as: :json
    assert_response :success

    json = JSON.parse(response.body)
    player_details = json["player_details"]

    # New player should appear in player_details keyed by faction_id
    assert player_details.key?(faction.id.to_s), "New player should be included in prediction details"
    assert_equal NewPlayerDefaults.custom_rating, player_details[faction.id.to_s]["cr"]
  end
end
