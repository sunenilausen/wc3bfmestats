# README

WC3BFMESTATS is a ruby on rails webapp that uses data from recorded replays as well as manually entered lobbies to calculate elo, statistics, and more.

## Development

### Setup
```bash
bin/setup              # Initial setup: bundle install, db setup, etc.
bin/rails db:seed      # Seed factions and test data
```

### Run Server
```bash
bin/dev                # Start development server with all services
bin/rails server       # Start Rails server only
```

### Testing & Code Quality
```bash
bin/rails test                           # Run all tests
bin/rails test test/models/player_test.rb    # Run single test file
bin/rubocop                              # Ruby style linter
bin/brakeman                             # Security scanner
```

## Production Server

The application is deployed at **https://bfme.snaps.games** on server `157.90.158.244`.

### Deployment
```bash
bin/kamal deploy       # Deploy to production
bin/kamal redeploy     # Redeploy (faster, skips build if image exists)
```

### Remote Access
```bash
bin/kamal shell        # SSH into production container
bin/kamal console      # Rails console on production
bin/kamal logs         # Tail production logs
bin/kamal dbc          # Database console on production
```

### Clone Production Database to Local
```bash
scp root@157.90.158.244:/var/lib/docker/volumes/wc3bfmestats_storage/_data/production.sqlite3 ./storage/development.sqlite3
```

### Useful Production Commands
```bash
# Sync replays from wc3stats
bin/kamal app exec "bin/rails wc3stats:sync"

# Recalculate all ratings
bin/kamal app exec "bin/rails runner 'CustomRatingRecalculator.new.call; MlScoreRecalculator.new.call'"

# Refetch matches with incomplete data
bin/kamal app exec "bin/rails runner 'RefetchIgnoredJob.perform_now(50)'"

# Invalidate stats cache
bin/kamal app exec "bin/rails runner 'StatsCacheKey.invalidate!'"
```
