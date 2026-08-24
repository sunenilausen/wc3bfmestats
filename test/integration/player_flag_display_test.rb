require "test_helper"

# The flag is display-only, so what matters is that it actually reaches every
# page a player's name appears on - including the two that render from a cache.
class PlayerFlagDisplayTest < ActionDispatch::IntegrationTest
  FLAG = "🚩".freeze
  NOTE = "Feeds heroes and rage quits".freeze

  setup do
    @player = matches(:one).appearances.detect(&:player_id).player
    @player.update!(flagged: true, flag_note: NOTE)
  end

  test "players index shows the flag" do
    get players_url

    assert_response :success
    assert_select "td", text: /#{@player.nickname}/
    assert_includes response.body, FLAG
    assert_includes response.body, NOTE
  end

  test "player page shows the flag and the note" do
    get player_url(@player)

    assert_response :success
    assert_includes response.body, FLAG
    assert_includes response.body, NOTE
  end

  test "match page shows the flag next to the player" do
    get match_url(matches(:one))

    assert_response :success
    assert_includes response.body, FLAG
    assert_includes response.body, NOTE
  end

  test "lobby page shows the flag next to the player" do
    get new_lobby_url
    lobby = Lobby.last
    lobby.lobby_players.first.update!(player: @player)

    get lobby_url(lobby)

    assert_response :success
    assert_includes response.body, FLAG
    assert_includes response.body, NOTE
  end

  test "lobby edit page carries the flag into its search data" do
    get new_lobby_url
    lobby = Lobby.last
    lobby.lobby_players.first.update!(player: @player)

    get edit_lobby_url(lobby)

    assert_response :success
    assert_includes response.body, FLAG
    assert_includes response.body, NOTE
    assert_match(/"flagged":true/, response.body)
  end

  # The match page is fragment cached on match data, which a flag does not
  # touch - so this only works because the key mixes in the moderation token.
  # The test env runs a null store, so caching has to be turned on by hand here.
  test "unflagging removes it again from the cached match page" do
    with_caching do
      get match_url(matches(:one))
      assert_includes response.body, NOTE

      @player.update!(flagged: false)

      get match_url(matches(:one))
      assert_not_includes response.body, NOTE
      assert_not_includes response.body, FLAG
    end
  end

  # Same story for the lobby edit search list, which is cached by LobbyEditStats.
  test "unflagging removes it again from the cached lobby search data" do
    get new_lobby_url
    lobby = Lobby.last
    lobby.lobby_players.first.update!(player: @player)

    with_caching do
      get edit_lobby_url(lobby)
      assert_includes response.body, NOTE

      @player.update!(flagged: false)

      get edit_lobby_url(lobby)
      assert_not_includes response.body, NOTE
      assert_no_match(/"flagged":true/, response.body)
    end
  end

  private

    def with_caching
      original_store = Rails.cache
      original_controller_store = ActionController::Base.cache_store
      original_perform = ActionController::Base.perform_caching
      store = ActiveSupport::Cache::MemoryStore.new
      Rails.cache = store
      ActionController::Base.cache_store = store
      ActionController::Base.perform_caching = true
      yield
    ensure
      Rails.cache = original_store
      ActionController::Base.cache_store = original_controller_store
      ActionController::Base.perform_caching = original_perform
    end
end
