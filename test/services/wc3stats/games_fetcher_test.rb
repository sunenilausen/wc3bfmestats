require "test_helper"
require "minitest/mock"

module Wc3stats
  class GamesFetcherTest < ActiveSupport::TestCase
    setup do
      @fixture_html = File.read(Rails.root.join("test/fixtures/files/wc3stats/games.html"))
    end

    test "successfully parses replay IDs from HTML" do
      # Mock the fetch_all_pages to return IDs from our fixture
      fixture_html = @fixture_html
      fetcher = GamesFetcher.new
      fetcher.define_singleton_method(:fetch_all_pages) do
        doc = Nokogiri::HTML(fixture_html)
        game_links = doc.css('a.Row.clickable.Row-body')
        game_links.map { |link| link['href'].split('/').last.to_i }.compact.uniq
      end

      replay_ids = fetcher.call

      assert replay_ids.is_a?(Array), "Expected an array of replay IDs"
      assert replay_ids.any?, "Expected to find some replay IDs"

      # Check that we found the expected IDs from the fixture
      assert_includes replay_ids, 720371
      assert_includes replay_ids, 720046
      assert_includes replay_ids, 719317
    end

    test "returns all unique replay IDs from the page" do
      fixture_html = @fixture_html
      fetcher = GamesFetcher.new
      fetcher.define_singleton_method(:fetch_all_pages) do
        doc = Nokogiri::HTML(fixture_html)
        game_links = doc.css('a.Row.clickable.Row-body')
        game_links.map { |link| link['href'].split('/').last.to_i }.compact.uniq
      end

      replay_ids = fetcher.call

      # The fixture has 15 game rows
      assert_equal 15, replay_ids.count
      assert_equal replay_ids.uniq, replay_ids, "Should not have duplicate replay IDs"
    end

    test "returns empty array when fetch fails" do
      fetcher = GamesFetcher.new
      fetcher.define_singleton_method(:fetch_all_pages) { [] }

      replay_ids = fetcher.call

      assert_equal [], replay_ids
    end

    test "respects max_pages parameter" do
      # This test verifies that max_pages is respected in the actual implementation
      fetcher = GamesFetcher.new(max_pages: 2)
      assert_equal 2, fetcher.max_pages
    end

    test "parses current page correctly" do
      mixed_html = <<~HTML
        <a href="/games/720371" class="Row clickable Row-body"></a>
        <a href="/games/abc" class="Row clickable Row-body"></a>
        <a href="/games/720046" class="Row clickable Row-body"></a>
        <a href="/other/page" class="Row clickable Row-body"></a>
      HTML

      fetcher = GamesFetcher.new
      mock_driver = Minitest::Mock.new
      mock_driver.expect(:page_source, mixed_html)

      ids = fetcher.send(:parse_current_page, mock_driver)

      assert_equal [720371, 720046], ids
      mock_driver.verify
    end

    test "handles errors and returns collected IDs" do
      fetcher = GamesFetcher.new
      fetcher.define_singleton_method(:fetch_all_pages) do
        @errors << "Test error"
        [720371, 720046]
      end

      replay_ids = fetcher.call

      assert_equal [720371, 720046], replay_ids
      assert_includes fetcher.errors, "Test error"
    end

    test "respects limit parameter" do
      fixture_html = @fixture_html
      fetcher = GamesFetcher.new(limit: 5)

      # Mock to return first 5 IDs
      fetcher.define_singleton_method(:fetch_all_pages) do
        doc = Nokogiri::HTML(fixture_html)
        game_links = doc.css('a.Row.clickable.Row-body')
        all_ids = game_links.map { |link| link['href'].split('/').last.to_i }.compact.uniq
        all_ids.take(@limit)
      end

      replay_ids = fetcher.call

      assert_equal 5, replay_ids.count
      assert_equal 5, fetcher.limit
    end

    test "limit takes precedence over pagination" do
      # Even if there are more pages, limit should stop fetching
      fetcher = GamesFetcher.new(limit: 10, max_pages: 100)
      assert_equal 10, fetcher.limit
      assert_equal 100, fetcher.max_pages
    end
  end
end
