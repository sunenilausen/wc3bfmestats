require "net/http"
require "json"

module Wc3stats
  class ReplayFetcher
    BASE_URL = "https://api.wc3stats.com/replays"

    attr_reader :replay_id, :response, :errors

    def initialize(replay_id)
      @replay_id = replay_id
      @errors = []
    end

    def call
      fetch_from_api
      return false unless valid_response?

      save_replay
    end

    private

    def fetch_from_api
      uri = URI("#{BASE_URL}/#{replay_id}")
      @response = Net::HTTP.get_response(uri)
    rescue StandardError => e
      @errors << "Failed to fetch replay: #{e.message}"
      @response = nil
    end

    def valid_response?
      unless response&.is_a?(Net::HTTPSuccess)
        @errors << "API request failed: #{response&.code} #{response&.message}"
        return false
      end

      parsed_body = parse_response_body
      unless parsed_body && parsed_body["status"] == "OK"
        @errors << "Invalid API response: #{parsed_body&.dig('status') || 'unknown status'}"
        return false
      end

      true
    end

    def parse_response_body
      # Sanitize response by removing ASCII control characters (except whitespace)
      sanitized_body = response.body.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
      JSON.parse(sanitized_body)
    rescue JSON::ParserError => e
      @errors << "Failed to parse JSON response: #{e.message}"
      nil
    end

    def save_replay
      parsed_body = parse_response_body
      body_data = parsed_body["body"]

      wc3stats_replay = Wc3statsReplay.find_or_initialize_by(
        wc3stats_replay_id: body_data["id"]
      )

      wc3stats_replay.body = body_data

      if wc3stats_replay.save
        build_match(wc3stats_replay)
        wc3stats_replay
      else
        @errors << "Failed to save replay: #{wc3stats_replay.errors.full_messages.join(', ')}"
        false
      end
    end

    def build_match(wc3stats_replay)
      match_builder = MatchBuilder.new(wc3stats_replay)
      unless match_builder.call
        @errors.concat(match_builder.errors)
      end
    end
  end
end
