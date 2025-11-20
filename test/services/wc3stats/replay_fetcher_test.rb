require "test_helper"
require "webmock/minitest"

module Wc3stats
  class ReplayFetcherTest < ActiveSupport::TestCase
    setup do
      @replay_id = 720046
      @api_url = "https://api.wc3stats.com/replays/#{@replay_id}"
      @fixture_json = File.read(Rails.root.join("test/fixtures/files/wc3stats/replays/720046-shortened.json"))
      @fixture_data = JSON.parse(@fixture_json)
    end

    test "successfully fetches and saves replay data" do
      stub_request(:get, @api_url).to_return(status: 200, body: @fixture_json)

      fetcher = ReplayFetcher.new(@replay_id)
      result = fetcher.call

      assert result.is_a?(Wc3statsReplay), "Expected a Wc3statsReplay instance"
      assert_equal @replay_id, result.wc3stats_replay_id
      assert_equal "LOTR BFME", result.game_name
      assert_equal "BFME", result.map_name
      assert_equal 2650, result.game_length
    end

    test "returns false and sets errors when API request fails" do
      stub_request(:get, @api_url).to_return(status: 500, body: "Internal Server Error")

      fetcher = ReplayFetcher.new(@replay_id)
      result = fetcher.call

      assert_equal false, result
      assert fetcher.errors.any? { |e| e.include?("API request failed") }
    end

    test "returns false and sets errors when JSON is invalid" do
      stub_request(:get, @api_url).to_return(status: 200, body: "invalid json")

      fetcher = ReplayFetcher.new(@replay_id)
      result = fetcher.call

      assert_equal false, result
      assert fetcher.errors.any? { |e| e.include?("Failed to parse JSON") }
    end

    test "returns false and sets errors when API status is not OK" do
      error_response = { status: "ERROR", code: 404, body: nil }.to_json
      stub_request(:get, @api_url).to_return(status: 200, body: error_response)

      fetcher = ReplayFetcher.new(@replay_id)
      result = fetcher.call

      assert_equal false, result
      assert fetcher.errors.any? { |e| e.include?("Invalid API response") }
    end

    test "updates existing replay if it already exists" do
      stub_request(:get, @api_url).to_return(status: 200, body: @fixture_json)

      # Create initial replay
      existing_replay = Wc3statsReplay.create!(
        wc3stats_replay_id: @replay_id,
        body: { "name" => "Old Name" }
      )

      fetcher = ReplayFetcher.new(@replay_id)
      result = fetcher.call

      assert_equal existing_replay.id, result.id, "Should update existing replay"
      assert_equal "LOTR BFME", result.game_name, "Should update the body"
    end

    test "handles network errors gracefully" do
      stub_request(:get, @api_url).to_raise(StandardError.new("Network error"))

      fetcher = ReplayFetcher.new(@replay_id)
      result = fetcher.call

      assert_equal false, result
      assert fetcher.errors.any? { |e| e.include?("Failed to fetch replay") }
      assert fetcher.errors.any? { |e| e.include?("Network error") }
    end
  end
end
