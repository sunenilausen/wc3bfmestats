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

## Recalculating Ratings

Ratings are derived data: every rating, PERF score, faction stat and stored prediction is rebuilt
from match history by walking every non-ignored match in chronological order. Nothing is
incremental, so a recalculation is always safe to re-run and always produces the same result.

**Recalculate everything (the usual command):**
```bash
bin/rails wc3stats:recalculate
```
Runs APM backfill → Custom Rating → PERF scores → player faction stats → stay/leave → cache
invalidation. Takes about **65 seconds** for ~1,900 matches. Use this after changing any rating
constant, contribution weight or prediction formula.

**Recalculate as part of importing new replays:**
```bash
bin/rails wc3stats:sync
```
The 13-step full sync: fetches and imports replays, builds matches, fixes encoding and ordering,
then runs the same recalculation chain at the end. Use this when you want new games *and* fresh
ratings.

**Custom Rating only** (skips PERF, faction stats and stay/leave — faster when you are only
iterating on the CR algorithm):
```bash
bin/rails custom_rating:recalculate
```

**From the console**, e.g. to run a single recalculator:
```bash
bin/rails runner 'CustomRatingRecalculator.new.call'
bin/rails runner 'MlScoreRecalculator.new.call'          # PERF scores
bin/rails runner 'PlayerFactionStatsCalculator.new.call'
bin/rails runner 'StayLeaveRecalculator.new.call'
bin/rails cache:invalidate                               # always finish with this
```

### On production
```bash
bin/kamal app exec "bin/rails wc3stats:recalculate"
```
Or the pieces individually:
```bash
bin/kamal app exec "bin/rails runner 'CustomRatingRecalculator.new.call; MlScoreRecalculator.new.call'"
bin/kamal app exec "bin/rails cache:invalidate"
```

### What triggers a recalculation by itself

- **Creating or editing a match in the UI** enqueues `RatingRecalculationJob`, which runs the same
  chain in the background. A banner appears site-wide while it runs
  (`RatingRecalculationStatus.in_progress?`), warning that ratings are temporarily inaccurate.
- **The Sync button** on the matches page enqueues `Wc3statsSyncJob`, which imports recent replays
  and then recalculates.
- Only the *newest* match can be processed incrementally
  (`CustomRatingRecalculator.process_match_if_latest`); anything older forces a full walk, because
  every later match depends on the ratings going into it.

### Notes

- The whole recalculation runs inside a transaction, so the site keeps serving the old ratings until
  it commits.
- `ml_score_at_match` is written once and never overwritten, which is what makes repeated
  recalculations reproduce identical predictions. `games_played_before_match`,
  `faction_games_before_match` and `streak_before_match` are recomputed each time from match order.
- **Always invalidate the stats cache afterwards** if you ran a recalculator directly rather than
  through a rake task — the rake tasks and the job already do it. Kamal deploys invalidate it via
  the post-deploy hook.

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

# Recalculate all ratings (see "Recalculating Ratings" above)
bin/kamal app exec "bin/rails wc3stats:recalculate"

# Refetch matches with incomplete data
bin/kamal app exec "bin/rails runner 'RefetchIgnoredJob.perform_now(50)'"

# Invalidate stats cache
bin/kamal app exec "bin/rails cache:invalidate"
```
