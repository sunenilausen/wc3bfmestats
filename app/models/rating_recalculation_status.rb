# Tracks when ratings are being recalculated so the UI can show a warning
# Uses a file-based lock to work across processes (rake tasks, web server, etc.)
class RatingRecalculationStatus
  # Default timeout in case recalculation crashes without clearing status
  TIMEOUT = 10.minutes

  class << self
    def start!
      FileUtils.mkdir_p(File.dirname(status_file))
      File.write(status_file, Time.current.iso8601)
    end

    def finish!
      File.delete(status_file) if File.exist?(status_file)
    end

    def in_progress?
      return false unless File.exist?(status_file)

      # Check if status file is stale (older than timeout)
      if File.mtime(status_file) < TIMEOUT.ago
        finish! # Clean up stale file
        return false
      end

      true
    end

    def started_at
      return nil unless File.exist?(status_file)
      Time.parse(File.read(status_file)) rescue File.mtime(status_file)
    end

    private

    def status_file
      Rails.root.join("tmp", "rating_recalculation.lock")
    end
  end
end
