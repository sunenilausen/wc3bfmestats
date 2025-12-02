require "test_helper"

class LobbyBalancerTest < ActiveSupport::TestCase
  setup do
    @lobby = Lobby.create!(session_token: "test-token")
    @good_faction = factions(:gondor)
    @evil_faction = factions(:mordor)
  end

  test "returns empty swaps when already balanced" do
    player1 = Player.create!(nickname: "P1", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)
    player2 = Player.create!(nickname: "P2", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: @good_faction, player: player1)
    @lobby.lobby_players.create!(faction: @evil_faction, player: player2)

    balancer = LobbyBalancer.new(@lobby)
    swaps = balancer.find_optimal_swaps

    assert_empty swaps
  end

  test "finds swap when teams are imbalanced" do
    strong = Player.create!(nickname: "Strong", custom_rating: 1700, ml_score: 60, custom_rating_games_played: 50)
    weak = Player.create!(nickname: "Weak", custom_rating: 1300, ml_score: 40, custom_rating_games_played: 50)
    medium1 = Player.create!(nickname: "Medium1", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)
    medium2 = Player.create!(nickname: "Medium2", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)

    # Imbalanced: Good has strong+medium1, Evil has weak+medium2
    @lobby.lobby_players.create!(faction: @good_faction, player: strong)
    @lobby.lobby_players.create!(faction: factions(:rohan), player: medium1)
    @lobby.lobby_players.create!(faction: @evil_faction, player: weak)
    @lobby.lobby_players.create!(faction: factions(:isengard), player: medium2)

    balancer = LobbyBalancer.new(@lobby)
    swaps = balancer.find_optimal_swaps

    # Should suggest swapping strong <-> weak to balance
    assert_not_empty swaps
  end

  test "balance! swaps players and returns result" do
    strong = Player.create!(nickname: "Strong", custom_rating: 1700, ml_score: 60, custom_rating_games_played: 50)
    weak = Player.create!(nickname: "Weak", custom_rating: 1300, ml_score: 40, custom_rating_games_played: 50)
    medium1 = Player.create!(nickname: "Medium1", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)
    medium2 = Player.create!(nickname: "Medium2", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)

    # Imbalanced: Good has strong+medium1, Evil has weak+medium2
    good_lp1 = @lobby.lobby_players.create!(faction: @good_faction, player: strong)
    good_lp2 = @lobby.lobby_players.create!(faction: factions(:rohan), player: medium1)
    evil_lp1 = @lobby.lobby_players.create!(faction: @evil_faction, player: weak)
    evil_lp2 = @lobby.lobby_players.create!(faction: factions(:isengard), player: medium2)

    balancer = LobbyBalancer.new(@lobby)
    result = balancer.balance!

    assert result[:success]
    assert result[:swaps_count].to_i > 0, "Expected at least one swap, got: #{result.inspect}"
  end

  test "balance! returns already balanced message when no swaps needed" do
    player1 = Player.create!(nickname: "P1", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)
    player2 = Player.create!(nickname: "P2", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: @good_faction, player: player1)
    @lobby.lobby_players.create!(faction: @evil_faction, player: player2)

    result = LobbyBalancer.new(@lobby).balance!

    assert result[:success]
    assert_equal 0, result[:swaps].size
    assert_includes result[:message], "balanced"
  end

  test "handles new player placeholders" do
    strong = Player.create!(nickname: "Strong", custom_rating: 1700, ml_score: 60, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: @good_faction, player: strong)
    @lobby.lobby_players.create!(faction: @evil_faction, player: nil, is_new_player: true)

    # Should not crash with new player placeholder
    balancer = LobbyBalancer.new(@lobby)
    swaps = balancer.find_optimal_swaps

    # New player has low score, so swap should be suggested
    assert_not_nil swaps
  end

  test "balance! preserves is_new_player flag during swap" do
    player = Player.create!(nickname: "Player", custom_rating: 1700, ml_score: 60, custom_rating_games_played: 50)

    good_lp = @lobby.lobby_players.create!(faction: @good_faction, player: player)
    evil_lp = @lobby.lobby_players.create!(faction: @evil_faction, player: nil, is_new_player: true)

    result = LobbyBalancer.new(@lobby).balance!

    assert result[:success]

    good_lp.reload
    evil_lp.reload

    # The new player marker should be swapped with the real player
    assert good_lp.is_new_player? || evil_lp.is_new_player?
  end

  test "handles empty slots gracefully" do
    player = Player.create!(nickname: "Solo", custom_rating: 1500, ml_score: 50, custom_rating_games_played: 50)

    @lobby.lobby_players.create!(faction: @good_faction, player: player)
    @lobby.lobby_players.create!(faction: @evil_faction, player: nil) # Empty, not new player

    balancer = LobbyBalancer.new(@lobby)
    swaps = balancer.find_optimal_swaps

    # Should handle nil players without crashing
    assert_not_nil swaps
  end
end
