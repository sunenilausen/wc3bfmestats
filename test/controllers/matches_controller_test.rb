require "test_helper"

class MatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @match = matches(:one)
    @admin = users(:admin)
  end

  test "should get index" do
    get matches_url
    assert_response :success
  end

  test "should get new as admin" do
    sign_in @admin
    get new_match_url
    assert_response :success
  end

  test "should redirect new when not admin" do
    get new_match_url
    assert_redirected_to root_path
  end

  test "should create match as admin" do
    sign_in @admin

    assert_difference("Match.count") do
      post matches_url, params: {
        match: {
          uploaded_at: @match.uploaded_at,
          seconds: @match.seconds,
          good_victory: true,
          appearances_attributes: {
            "0" => { player_id: players(:one).id, faction_id: factions(:gondor).id, unit_kills: 120, hero_kills: 6 },
            "1" => { player_id: players(:two).id, faction_id: factions(:rohan).id, unit_kills: 95, hero_kills: 4 },
            "2" => { player_id: players(:three).id, faction_id: factions(:dol_amroth).id, unit_kills: 110, hero_kills: 5 },
            "3" => { player_id: players(:four).id, faction_id: factions(:fellowship).id, unit_kills: 88, hero_kills: 3 },
            "4" => { player_id: players(:five).id, faction_id: factions(:fangorn).id, unit_kills: 102, hero_kills: 4 },
            "5" => { player_id: players(:six).id, faction_id: factions(:isengard).id, unit_kills: 85, hero_kills: 3 },
            "6" => { player_id: players(:seven).id, faction_id: factions(:easterlings).id, unit_kills: 78, hero_kills: 2 },
            "7" => { player_id: players(:eight).id, faction_id: factions(:harad).id, unit_kills: 92, hero_kills: 4 },
            "8" => { player_id: players(:nine).id, faction_id: factions(:minas_morgul).id, unit_kills: 70, hero_kills: 2 },
            "9" => { player_id: players(:ten).id, faction_id: factions(:mordor).id, unit_kills: 105, hero_kills: 5 }
          }
        }
      }
    end

    assert_redirected_to match_url(Match.last)

    # Verify custom ratings were calculated and stored
    match = Match.last
    good_appearance = match.appearances.find_by(player_id: players(:one).id)
    evil_appearance = match.appearances.find_by(player_id: players(:six).id)

    # Check that custom_rating was set (rating at time of match)
    assert_not_nil good_appearance.custom_rating, "Good team appearance should have custom_rating set"
    assert_not_nil evil_appearance.custom_rating, "Evil team appearance should have custom_rating set"

    # Check that custom_rating_change was calculated
    assert_not_nil good_appearance.custom_rating_change, "Good team appearance should have custom_rating_change set"
    assert_not_nil evil_appearance.custom_rating_change, "Evil team appearance should have custom_rating_change set"

    # Good team won, so they should gain rating and evil should lose rating
    assert_operator good_appearance.custom_rating_change, :>, 0, "Winning team should have positive custom_rating_change"
    assert_operator evil_appearance.custom_rating_change, :<, 0, "Losing team should have negative custom_rating_change"

    # Check that player's current custom_rating was updated correctly
    # Player's current rating should equal their rating at match time + the change
    players(:one).reload
    players(:six).reload
    assert_equal good_appearance.custom_rating + good_appearance.custom_rating_change, players(:one).custom_rating, "Player's custom_rating should be updated"
    assert_equal evil_appearance.custom_rating + evil_appearance.custom_rating_change, players(:six).custom_rating, "Player's custom_rating should be updated"
  end

  test "should show match" do
    get match_url(@match)
    assert_response :success
  end

  test "should get edit as admin" do
    sign_in @admin
    get edit_match_url(@match)
    assert_response :success
  end

  test "should redirect edit when not admin" do
    get edit_match_url(@match)
    assert_redirected_to root_path
  end

  test "should update match as admin" do
    sign_in @admin

    patch match_url(@match), params: {
      match: {
        uploaded_at: @match.uploaded_at,
        seconds: @match.seconds,
        good_victory: false,
        appearances_attributes: {
          "0" => { id: appearances(:gondor_one).id, player_id: players(:one).id, faction_id: factions(:gondor).id, unit_kills: 130, hero_kills: 7 },
          "1" => { id: appearances(:rohan_one).id, player_id: players(:two).id, faction_id: factions(:rohan).id, unit_kills: 100, hero_kills: 5 },
          "2" => { id: appearances(:dol_amroth_one).id, player_id: players(:three).id, faction_id: factions(:dol_amroth).id, unit_kills: 115, hero_kills: 6 },
          "3" => { id: appearances(:fellowship_one).id, player_id: players(:four).id, faction_id: factions(:fellowship).id, unit_kills: 90, hero_kills: 4 },
          "4" => { id: appearances(:fangorn_one).id, player_id: players(:five).id, faction_id: factions(:fangorn).id, unit_kills: 105, hero_kills: 5 },
          "5" => { id: appearances(:isengard_one).id, player_id: players(:six).id, faction_id: factions(:isengard).id, unit_kills: 140, hero_kills: 8 },
          "6" => { id: appearances(:easterlings_one).id, player_id: players(:seven).id, faction_id: factions(:easterlings).id, unit_kills: 125, hero_kills: 6 },
          "7" => { id: appearances(:harad_one).id, player_id: players(:eight).id, faction_id: factions(:harad).id, unit_kills: 135, hero_kills: 7 },
          "8" => { id: appearances(:minas_morgul_one).id, player_id: players(:nine).id, faction_id: factions(:minas_morgul).id, unit_kills: 110, hero_kills: 5 },
          "9" => { id: appearances(:mordor_one).id, player_id: players(:ten).id, faction_id: factions(:mordor).id, unit_kills: 145, hero_kills: 9 }
        }
      }
    }

    assert_redirected_to match_url(@match)

    # Verify custom ratings were recalculated
    @match.reload
    good_appearance = @match.appearances.find_by(player_id: players(:one).id)
    evil_appearance = @match.appearances.find_by(player_id: players(:six).id)

    # Check that custom_rating was updated
    assert_not_nil good_appearance.custom_rating, "Good team appearance should have custom_rating set"
    assert_not_nil evil_appearance.custom_rating, "Evil team appearance should have custom_rating set"

    # Check that custom_rating_change was recalculated
    assert_not_nil good_appearance.custom_rating_change, "Good team appearance should have custom_rating_change set"
    assert_not_nil evil_appearance.custom_rating_change, "Evil team appearance should have custom_rating_change set"

    # Evil team won (good_victory: false), so good should lose and evil should gain
    assert_operator good_appearance.custom_rating_change, :<, 0, "Losing team should have negative custom_rating_change"
    assert_operator evil_appearance.custom_rating_change, :>, 0, "Winning team should have positive custom_rating_change"

    # Verify player ratings were updated (CustomRatingRecalculator recalculates from scratch)
    players(:one).reload
    players(:six).reload
    assert_not_nil players(:one).custom_rating, "Player should have custom_rating set"
    assert_not_nil players(:six).custom_rating, "Player should have custom_rating set"
  end

  test "should not update match when not admin" do
    patch match_url(@match), params: { match: { good_victory: false } }
    assert_redirected_to root_path
  end

  test "should destroy match as admin" do
    sign_in @admin
    assert_difference("Match.count", -1) do
      delete match_url(@match)
    end

    assert_redirected_to matches_url
  end

  test "should not destroy match when not admin" do
    assert_no_difference("Match.count") do
      delete match_url(@match)
    end

    assert_redirected_to root_path
  end
end
