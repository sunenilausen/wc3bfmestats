require "test_helper"

class AppearancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @appearance = appearances(:gondor_one)
  end

  test "should get index" do
    get appearances_url
    assert_response :success
  end

  test "should show appearance" do
    get appearance_url(@appearance)
    assert_response :success
  end
end
