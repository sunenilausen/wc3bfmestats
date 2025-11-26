require "test_helper"

class FactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @faction = factions(:gondor)
    @admin = users(:admin)
  end

  test "should get index" do
    get factions_url
    assert_response :success
  end

  test "should show faction" do
    get faction_url(@faction)
    assert_response :success
  end

  test "should get edit as admin" do
    sign_in @admin
    get edit_faction_url(@faction)
    assert_response :success
  end

  test "should redirect edit when not admin" do
    get edit_faction_url(@faction)
    assert_redirected_to root_path
  end

  test "should update faction as admin" do
    sign_in @admin
    patch faction_url(@faction), params: { faction: { color: @faction.color, good: @faction.good, name: @faction.name } }
    assert_redirected_to faction_url(@faction)
  end

  test "should not update faction when not admin" do
    patch faction_url(@faction), params: { faction: { name: "hacked" } }
    assert_redirected_to root_path
  end
end
