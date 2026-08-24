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

    # Admin flags on players change nothing about matches, so they cannot move
    # the key above - two flags renders identically to none as far as match data
    # goes. Anything that renders a flag inside a cache (the match page, the
    # lobby edit search list) mixes this token in as well.
    def moderation_key
      Rails.cache.fetch("player_moderation_key", expires_in: 1.hour) do
        compute_moderation_key
      end
    end

    def invalidate_moderation!
      Rails.cache.delete("player_moderation_key")
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

    # A digest of who is flagged and what their note says, rather than a
    # timestamp: two edits in the same second would otherwise hash the same and
    # leave the second one invisible behind a cache.
    def compute_moderation_key
      flags = Player.flagged.order(:id).pluck(:id, :flag_note)
      return "none" if flags.empty?

      Digest::MD5.hexdigest(flags.to_s)
    end
  end
end
