# frozen_string_literal: true

class Ahoy::Store < Ahoy::DatabaseStore
end

# GDPR-friendly configuration

# Disable cookies entirely
Ahoy.cookies = :none

# Mask IP addresses for privacy (last octet set to 0)
Ahoy.mask_ips = true

# Disable JavaScript tracking API
Ahoy.api = false

# Disable geocoding
Ahoy.geocode = false

# Track bots for accurate page view counts (optional, set to false to exclude)
Ahoy.track_bots = false

# Use server-side visits only (no client-side tracking)
Ahoy.server_side_visits = :when_needed
