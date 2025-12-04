require "test_helper"

class PlayerMergerTest < ActiveSupport::TestCase
  setup do
    @primary = players(:one)
    @mergeable = players(:unused)
  end

  test "merges appearances from mergeable to primary" do
    # Create an appearance for mergeable player in match two (primary doesn't have one there)
    match = matches(:two)
    faction = factions(:gondor)
    mergeable_appearance = Appearance.create!(
      player: @mergeable,
      match: match,
      faction: faction,
      hero_kills: 10,
      unit_kills: 100
    )

    initial_primary_appearances = @primary.appearances.count

    result = PlayerMerger.new(@primary, @mergeable).merge

    assert result.success?, "Expected merge to succeed: #{result.message}"
    assert_equal initial_primary_appearances + 1, @primary.reload.appearances.count
    assert_equal @primary.id, mergeable_appearance.reload.player_id
  end

  test "transfers lobby_players from mergeable to primary" do
    lobby = Lobby.create!(session_token: "test-token")
    faction = factions(:gondor)
    lobby_player = LobbyPlayer.create!(
      lobby: lobby,
      faction: faction,
      player: @mergeable
    )

    result = PlayerMerger.new(@primary, @mergeable).merge

    assert result.success?
    assert_equal @primary.id, lobby_player.reload.player_id
  end

  test "transfers lobby_observers from mergeable to primary" do
    lobby = Lobby.create!(session_token: "test-token")
    observer = LobbyObserver.create!(
      lobby: lobby,
      player: @mergeable
    )

    result = PlayerMerger.new(@primary, @mergeable).merge

    assert result.success?
    assert_equal @primary.id, observer.reload.player_id
  end

  test "copies missing fields from mergeable to primary" do
    @primary.update!(alternative_name: nil, battletag: nil)
    @mergeable.update!(alternative_name: "Alt Name", battletag: "MergePlayer#1234")

    result = PlayerMerger.new(@primary, @mergeable).merge

    assert result.success?
    @primary.reload
    assert_equal "Alt Name", @primary.alternative_name
    assert_equal "MergePlayer#1234", @primary.battletag
  end

  test "does not overwrite existing fields on primary" do
    @primary.update!(alternative_name: "Primary Alt", battletag: "Primary#1234")
    @mergeable.update!(alternative_name: "Mergeable Alt", battletag: "Mergeable#5678")

    result = PlayerMerger.new(@primary, @mergeable).merge

    assert result.success?
    @primary.reload
    assert_equal "Primary Alt", @primary.alternative_name
    assert_equal "Primary#1234", @primary.battletag
  end

  test "destroys mergeable player after merge" do
    mergeable_id = @mergeable.id

    result = PlayerMerger.new(@primary, @mergeable).merge

    assert result.success?
    assert_nil Player.find_by(id: mergeable_id)
  end

  test "fails when primary is nil" do
    result = PlayerMerger.new(nil, @mergeable).merge

    assert_not result.success?
    assert_equal "Primary player is nil", result.message
  end

  test "fails when mergeable is nil" do
    result = PlayerMerger.new(@primary, nil).merge

    assert_not result.success?
    assert_equal "Mergeable player is nil", result.message
  end

  test "fails when merging player into itself" do
    result = PlayerMerger.new(@primary, @primary).merge

    assert_not result.success?
    assert_equal "Cannot merge a player into itself", result.message
  end

  test "handles duplicate appearances in same match" do
    match = matches(:one)

    # Primary already has appearance in match one (from fixtures)
    # Create another appearance for mergeable in same match
    mergeable_appearance = Appearance.create!(
      player: @mergeable,
      match: match,
      faction: factions(:rohan),
      hero_kills: 10,
      unit_kills: 100
    )

    primary_appearances_before = @primary.appearances.count

    result = PlayerMerger.new(@primary, @mergeable).merge

    assert result.success?
    # Mergeable's appearance should be destroyed (duplicate match)
    assert_nil Appearance.find_by(id: mergeable_appearance.id)
    # Primary's appearance count should remain the same
    assert_equal primary_appearances_before, @primary.reload.appearances.count
  end

  test "returns success message with player info" do
    result = PlayerMerger.new(@primary, @mergeable).merge

    assert result.success?
    assert_includes result.message, @primary.nickname
    assert_includes result.message, @mergeable.nickname
    assert_includes result.message, @primary.id.to_s
  end

  test "preserves mergeable battletag in alternative_battletags" do
    @primary.update!(battletag: "Primary#1234", alternative_battletags: [])
    @mergeable.update!(battletag: "Mergeable#5678")

    result = PlayerMerger.new(@primary, @mergeable).merge

    assert result.success?
    @primary.reload
    assert_includes @primary.alternative_battletags, "Mergeable#5678"
  end

  test "preserves mergeable alternative_battletags in primary" do
    @primary.update!(battletag: "Primary#1234", alternative_battletags: ["Old#1111"])
    @mergeable.update!(battletag: "Mergeable#5678", alternative_battletags: ["AltMerge#9999"])

    result = PlayerMerger.new(@primary, @mergeable).merge

    assert result.success?
    @primary.reload
    assert_includes @primary.alternative_battletags, "Old#1111"
    assert_includes @primary.alternative_battletags, "Mergeable#5678"
    assert_includes @primary.alternative_battletags, "AltMerge#9999"
    assert_not_includes @primary.alternative_battletags, "Primary#1234"
  end
end
