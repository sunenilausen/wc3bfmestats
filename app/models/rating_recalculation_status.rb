# Tracks when ratings are being recalculated so the UI can show a warning
# Uses Rails cache for simple, ephemeral state tracking
class RatingRecalculationStatus
  CACHE_KEY = "rating_recalculation_status".freeze
  # Default timeout in case recalculation crashes without clearing status
  TIMEOUT = 10.minutes

  class << self
    def start!
      Rails.cache.write(CACHE_KEY, { started_at: Time.current }, expires_in: TIMEOUT)
    end

    def finish!
      Rails.cache.delete(CACHE_KEY)
    end

    def in_progress?
      Rails.cache.exist?(CACHE_KEY)
    end

    def started_at
      status = Rails.cache.read(CACHE_KEY)
      status&.dig(:started_at)
    end
  end
end
