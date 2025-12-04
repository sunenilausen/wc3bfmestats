require "test_helper"

class Admin::PlayerMergesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @source_player = Player.create!(nickname: "SourcePlayer", battletag: "Source#1234")
    @target_player = Player.create!(nickname: "TargetPlayer", battletag: "Target#5678")
  end

  test "should redirect non-admin users from merge page" do
    get new_admin_player_merge_path(@source_player)
    assert_redirected_to new_user_session_path
  end

  test "should redirect non-admin logged in users from merge page" do
    regular_user = users(:one)
    sign_in regular_user
    get new_admin_player_merge_path(@source_player)
    assert_redirected_to root_path
  end

  test "should get new for admin users" do
    sign_in @admin
    get new_admin_player_merge_path(@source_player)
    assert_response :success
    assert_select "h1", /Merge Player/
  end

  test "should merge players and redirect to target" do
    sign_in @admin

    # Create a match and appearance for source player
    faction = factions(:gondor)
    match = Match.create!(good_victory: true, uploaded_at: Time.current)
    Appearance.create!(player: @source_player, match: match, faction: faction)

    assert_equal 1, @source_player.appearances.count
    assert_equal 0, @target_player.appearances.count

    post admin_player_merge_path(@source_player), params: { target_player_id: @target_player.id }

    # Check for errors
    if flash[:alert]
      flunk "Merge failed with alert: #{flash[:alert]}"
    end

    assert_redirected_to player_path(@target_player)
    follow_redirect!
    assert_match /Successfully merged/, flash[:notice]

    # Source player should be deleted
    assert_nil Player.find_by(id: @source_player.id)

    # Target player should have the appearance
    @target_player.reload
    assert_equal 1, @target_player.appearances.count
  end

  test "should not allow merging player with themselves" do
    sign_in @admin

    assert_no_difference("Player.count") do
      post admin_player_merge_path(@source_player), params: { target_player_id: @source_player.id }
    end

    assert_redirected_to new_admin_player_merge_path(@source_player)
    assert_match /Cannot merge a player into itself/, flash[:alert]
  end
end
