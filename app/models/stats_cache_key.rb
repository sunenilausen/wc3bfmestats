# Provides a global cache key for stats that only change when matches are updated
# Usage: Rails.cache.fetch(["player_stats", player.id, StatsCacheKey.key]) { ... }
class StatsCacheKey
  class << self
    def key
      Rails.cache.fetch("stats_cache_key", expires_in: 1.hour) do
        compute_key
      end
    end

    # Call this when matches are created/updated/destroyed to invalidate stats cache
    def invalidate!
      Rails.cache.delete("stats_cache_key")
    end

    private

    def compute_key
      # Use the maximum updated_at from matches/appearances and counts as cache key
      # This ensures cache invalidates when any match or appearance changes
      match_max = Match.maximum(:updated_at)&.to_i || 0
      match_count = Match.count
      appearance_max = Appearance.maximum(:updated_at)&.to_i || 0
      "#{match_max}-#{match_count}-#{appearance_max}"
    end
  end
end
