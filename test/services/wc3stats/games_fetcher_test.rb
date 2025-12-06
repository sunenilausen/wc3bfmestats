require "test_helper"
require "webmock/minitest"

module Wc3stats
  class GamesFetcherTest < ActiveSupport::TestCase
    setup do
      @api_response = {
        "status" => "OK",
        "code" => 200,
        "pagination" => {
          "totalItems" => 5
        },
        "body" => [
          { "id" => 231, "name" => "LOTR BFME", "map" => "BFME" },
          { "id" => 233, "name" => "LOTR BFME RM", "map" => "BFME" },
          { "id" => 720046, "name" => "BFME Test", "map" => "BFME" },
          { "id" => 720371, "name" => "BFME Game", "map" => "BFME" },
          { "id" => 719317, "name" => "BFME Match", "map" => "BFME" }
        ]
      }
    end

    test "successfully fetches replay IDs from API" do
      stub_request(:get, "https://api.wc3stats.com/replays?limit=0&search=BFME")
        .to_return(status: 200, body: @api_response.to_json, headers: { "Content-Type" => "application/json" })

      fetcher = GamesFetcher.new(search_term: "BFME")
      replay_ids = fetcher.call

      assert replay_ids.is_a?(Array), "Expected an array of replay IDs"
      assert_equal 5, replay_ids.count
      assert_includes replay_ids, 720371
      assert_includes replay_ids, 720046
      assert_includes replay_ids, 719317
      assert_empty fetcher.errors
    end

    test "returns IDs sorted by ID (oldest first)" do
      stub_request(:get, "https://api.wc3stats.com/replays?limit=0&search=BFME")
        .to_return(status: 200, body: @api_response.to_json, headers: { "Content-Type" => "application/json" })

      fetcher = GamesFetcher.new(search_term: "BFME")
      replay_ids = fetcher.call

      assert_equal [ 231, 233, 719317, 720046, 720371 ], replay_ids
    end

    test "returns empty array when API fails" do
      stub_request(:get, "https://api.wc3stats.com/replays?limit=0")
        .to_return(status: 500, body: "Internal Server Error")

      fetcher = GamesFetcher.new
      replay_ids = fetcher.call

      assert_equal [], replay_ids
      assert fetcher.errors.any?
      assert_match(/API request failed/, fetcher.errors.first)
    end

    test "returns empty array when API returns error status" do
      error_response = { "status" => "ERROR", "message" => "Something went wrong" }
      stub_request(:get, "https://api.wc3stats.com/replays?limit=0")
        .to_return(status: 200, body: error_response.to_json, headers: { "Content-Type" => "application/json" })

      fetcher = GamesFetcher.new
      replay_ids = fetcher.call

      assert_equal [], replay_ids
      assert fetcher.errors.any?
      assert_match(/API returned error status/, fetcher.errors.first)
    end

    test "respects limit parameter by taking most recent IDs" do
      stub_request(:get, "https://api.wc3stats.com/replays?limit=0&search=BFME")
        .to_return(status: 200, body: @api_response.to_json, headers: { "Content-Type" => "application/json" })

      fetcher = GamesFetcher.new(search_term: "BFME", limit: 3)
      replay_ids = fetcher.call

      assert_equal 3, replay_ids.count
      # Should take the 3 most recent (highest IDs)
      assert_equal [ 719317, 720046, 720371 ], replay_ids
    end

    test "handles network errors gracefully" do
      stub_request(:get, "https://api.wc3stats.com/replays?limit=0")
        .to_raise(SocketError.new("Connection refused"))

      fetcher = GamesFetcher.new
      replay_ids = fetcher.call

      assert_equal [], replay_ids
      assert fetcher.errors.any?
      assert_match(/Failed to fetch replay IDs/, fetcher.errors.first)
    end

    test "handles invalid JSON response" do
      stub_request(:get, "https://api.wc3stats.com/replays?limit=0")
        .to_return(status: 200, body: "not valid json", headers: { "Content-Type" => "application/json" })

      fetcher = GamesFetcher.new
      replay_ids = fetcher.call

      assert_equal [], replay_ids
      assert fetcher.errors.any?
      assert_match(/Failed to parse API response/, fetcher.errors.first)
    end

    test "works without search term" do
      stub_request(:get, "https://api.wc3stats.com/replays?limit=0")
        .to_return(status: 200, body: @api_response.to_json, headers: { "Content-Type" => "application/json" })

      fetcher = GamesFetcher.new
      replay_ids = fetcher.call

      assert_equal 5, replay_ids.count
      assert_empty fetcher.errors
    end

    test "max_pages parameter is accepted for backwards compatibility" do
      stub_request(:get, "https://api.wc3stats.com/replays?limit=0")
        .to_return(status: 200, body: @api_response.to_json, headers: { "Content-Type" => "application/json" })

      # Should not raise error even though max_pages is no longer used
      fetcher = GamesFetcher.new(max_pages: 10)
      replay_ids = fetcher.call

      assert_equal 5, replay_ids.count
    end
  end
end
