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

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 30
      http.read_timeout = 300  # 5 minutes for large responses

      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

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
      # When using limit, order by desc to get most recent games first
      params[:order] = "desc" if limit && limit > 0

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

      # Sort by ID to maintain consistent order (oldest first for processing)
      replay_ids.sort!

      puts "  Found #{replay_ids.count} replay IDs (total available: #{data.dig('pagination', 'totalItems') || replays.count})"

      replay_ids
    rescue JSON::ParserError => e
      @errors << "Failed to parse API response: #{e.message}"
      []
    end
  end
end
