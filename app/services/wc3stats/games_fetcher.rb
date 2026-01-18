require "net/http"
require "json"

module Wc3stats
  class GamesFetcher
    API_URL = "https://api.wc3stats.com/replays"

    attr_reader :search_term, :errors, :limit

    def initialize(search_term: nil, max_pages: nil, limit: nil)
      @search_term = search_term
      @limit = limit
      # max_pages is no longer used with API approach, kept for backwards compatibility
      @errors = []
    end

    def call
      fetch_replay_ids
    end

    private

    def fetch_replay_ids
      uri = build_uri
      puts "  Fetching from API: #{uri}"

      response = Net::HTTP.get_response(uri)

      unless response.is_a?(Net::HTTPSuccess)
        @errors << "API request failed with status #{response.code}: #{response.message}"
        return []
      end

      parse_response(response.body)
    rescue StandardError => e
      @errors << "Failed to fetch replay IDs: #{e.message}"
      []
    end

    def build_uri
      # Use provided limit or 0 (which returns all results)
      params = { limit: limit && limit > 0 ? limit : 0 }
      params[:search] = search_term if search_term.present?

      uri = URI(API_URL)
      uri.query = URI.encode_www_form(params)
      uri
    end

    def parse_response(body)
      data = JSON.parse(body)

      unless data["status"] == "OK"
        @errors << "API returned error status: #{data['status']}"
        return []
      end

      replays = data["body"] || []
      replay_ids = replays.map { |replay| replay["id"] }.compact

      # Sort by ID to maintain consistent order (oldest first)
      replay_ids.sort!

      # Apply limit if specified
      if limit && limit > 0
        replay_ids = replay_ids.last(limit) # Take the most recent (highest IDs)
      end

      puts "  Found #{replay_ids.count} replay IDs (total available: #{data.dig('pagination', 'totalItems') || replays.count})"

      replay_ids
    rescue JSON::ParserError => e
      @errors << "Failed to parse API response: #{e.message}"
      []
    end
  end
end
