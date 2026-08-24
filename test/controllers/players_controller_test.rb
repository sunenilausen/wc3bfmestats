require "test_helper"

class PlayersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @player = players(:one)
    @admin = users(:admin)
  end

  test "should get index" do
    get players_url
    assert_response :success
  end

  test "should get new as admin" do
    sign_in @admin
    get new_player_url
    assert_response :success
  end

  test "should redirect new when not admin" do
    get new_player_url
    assert_redirected_to root_path
  end

  test "should create player as admin" do
    sign_in @admin
    assert_difference("Player.count") do
      post players_url, params: { player: { battlenet_name: @player.battlenet_name, battlenet_number: @player.battlenet_number, battletag: "new#{@player.battletag}", nickname: "New#{@player.nickname}", region: @player.region } }
    end

    assert_redirected_to player_url(Player.last)
  end

  test "should not create player when not admin" do
    assert_no_difference("Player.count") do
      post players_url, params: { player: { battlenet_name: @player.battlenet_name, battlenet_number: @player.battlenet_number, battletag: @player.battletag, nickname: @player.nickname, region: @player.region } }
    end

    assert_redirected_to root_path
  end

  test "should show player" do
    get player_url(@player)
    assert_response :success
  end

  test "should get edit as admin" do
    sign_in @admin
    get edit_player_url(@player)
    assert_response :success
  end

  test "should redirect edit when not admin" do
    get edit_player_url(@player)
    assert_redirected_to root_path
  end

  test "should update player as admin" do
    sign_in @admin
    patch player_url(@player), params: { player: { battlenet_name: @player.battlenet_name, battlenet_number: @player.battlenet_number, battletag: @player.battletag, nickname: @player.nickname, region: @player.region } }
    assert_redirected_to player_url(@player)
  end

  test "admin can flag a player with a note" do
    sign_in @admin
    patch player_url(@player), params: { player: { flagged: "1", flag_note: "Feeds heroes" } }

    @player.reload
    assert @player.flagged?
    assert_equal "Feeds heroes", @player.flag_note
  end

  test "admin can clear a flag" do
    @player.update!(flagged: true, flag_note: "Feeds heroes")
    sign_in @admin
    patch player_url(@player), params: { player: { flagged: "0" } }

    @player.reload
    assert_not @player.flagged?
    assert_nil @player.flagged_at
  end

  test "uploader cannot flag a player" do
    sign_in users(:uploader)
    patch player_url(@player), params: { player: { flagged: "1", flag_note: "Feeds heroes" } }

    assert_redirected_to root_path
    assert_not @player.reload.flagged?
  end

  test "should not update player when not admin" do
    patch player_url(@player), params: { player: { nickname: "hacked" } }
    assert_redirected_to root_path
  end

  test "should destroy player as admin" do
    sign_in @admin
    unused_player = players(:unused)
    assert_difference("Player.count", -1) do
      delete player_url(unused_player)
    end

    assert_redirected_to players_url
  end

  test "should not destroy player when not admin" do
    unused_player = players(:unused)
    assert_no_difference("Player.count") do
      delete player_url(unused_player)
    end

    assert_redirected_to root_path
  end
end
