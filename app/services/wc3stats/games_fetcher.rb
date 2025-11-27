require "selenium-webdriver"
require "nokogiri"

module Wc3stats
  class GamesFetcher
    BASE_URL = "https://wc3stats.com/games"

    attr_reader :search_term, :errors, :max_pages, :limit

    def initialize(search_term: nil, max_pages: nil, limit: nil)
      @search_term = search_term
      @max_pages = max_pages
      @limit = limit
      @errors = []
    end

    def call
      fetch_all_pages
    end

    private

    def fetch_all_pages
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument("--headless")
      options.add_argument("--disable-gpu")
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-dev-shm-usage")

      # Use system-installed Chromium binary if available
      options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"]

      # Configure service to use system ChromeDriver
      service_options = {}
      service_options[:path] = ENV["SE_CHROMEDRIVER"] if ENV["SE_CHROMEDRIVER"]
      service = Selenium::WebDriver::Chrome::Service.new(**service_options)

      driver = Selenium::WebDriver.for :chrome, options: options, service: service
      all_replay_ids = []
      page_count = 0

      begin
        driver.navigate.to BASE_URL

        # Wait for initial page load
        wait = Selenium::WebDriver::Wait.new(timeout: 10)
        wait.until { driver.find_element(css: 'a.Row.clickable.Row-body') }

        # If search term is provided, enter it in the search box
        if search_term
          search_input = driver.find_element(css: 'div.search input[type="text"]')
          search_input.clear
          search_input.send_keys(search_term)

          # Wait for filtering to happen
          sleep 1
        end

        loop do
          page_count += 1
          puts "Fetching page #{page_count}..." if Rails.env.development?

          # Extract IDs from current page
          page_ids = parse_current_page(driver)

          # If we have a limit, only add IDs up to the limit
          if limit
            remaining = limit - all_replay_ids.count
            if remaining > 0
              ids_to_add = page_ids.take(remaining)
              all_replay_ids.concat(ids_to_add)
              puts "  Found #{ids_to_add.count} IDs on page #{page_count} (limit: #{all_replay_ids.count}/#{limit})" if Rails.env.development?

              # If we've reached the limit, stop
              break if all_replay_ids.count >= limit
            else
              break
            end
          else
            all_replay_ids.concat(page_ids)
            puts "  Found #{page_ids.count} IDs on page #{page_count} (total: #{all_replay_ids.count})" if Rails.env.development?
          end

          # Check if we've reached max pages limit
          break if max_pages && page_count >= max_pages

          # Try to find and click the next button
          next_button = find_next_button(driver)
          break unless next_button

          # Click next and wait for new content
          next_button.click
          sleep 1.5 # Wait for page to load

          # Wait for table to update (check that we have new content)
          begin
            wait.until do
              # Wait for table to be present
              driver.find_element(css: 'a.Row.clickable.Row-body')
            end
          rescue Selenium::WebDriver::Error::TimeoutError
            puts "  No more content found" if Rails.env.development?
            break
          end
        end

        all_replay_ids.uniq
      rescue Selenium::WebDriver::Error::TimeoutError => e
        @errors << "Timeout waiting for page to load: #{e.message}"
        all_replay_ids.uniq
      rescue StandardError => e
        @errors << "Failed to fetch pages: #{e.message}"
        all_replay_ids.uniq
      ensure
        driver&.quit
      end
    end

    def parse_current_page(driver)
      doc = Nokogiri::HTML(driver.page_source)

      # Find all links with class "Row clickable Row-body"
      game_links = doc.css('a.Row.clickable.Row-body')

      replay_ids = game_links.map do |link|
        href = link['href']
        # Extract ID from href like "/games/720371"
        next unless href&.start_with?('/games/')

        game_id = href.split('/').last.to_i
        next if game_id.zero?

        game_id
      end.compact

      replay_ids
    rescue StandardError => e
      @errors << "Failed to parse HTML: #{e.message}"
      []
    end

    def find_next_button(driver)
      # Find the pagination next button (right arrow)
      # It's the last <li> in the pagination with an angle-right icon
      pagination = driver.find_elements(css: 'ul.Pagination li')
      return nil if pagination.empty?

      # The last <li> should be the next button
      next_li = pagination.last
      return nil unless next_li

      # Check if it has the right arrow icon
      next_button = next_li.find_element(css: 'a')
      icon = next_button.find_element(css: 'i.fa-angle-right')

      # Check if button is disabled (usually parent li doesn't have a link or has disabled class)
      return nil if next_li.attribute("class")&.include?("disabled")

      next_button
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # No next button found, we're on the last page
      nil
    end
  end
end
