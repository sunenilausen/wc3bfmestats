# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Rails 8.1 application for tracking Warcraft 3 Battle for Middle Earth (BfME) match statistics with ELO and Glicko-2 rating systems. Players compete as Good vs Evil factions, and the system calculates and tracks ratings based on match outcomes.

## Core Domain Model

The application uses a join-table architecture for many-to-many relationships:

- **Match**: Represents a game with `uploaded_at` (earliest wc3stats upload date), `seconds` (duration), `good_victory` (boolean), and ordering fields (`major_version`, `build_version`, `map_version`, `row_order`)
- **Player**: Battle.net user with `nickname`, `battletag`, `elo_rating`, `elo_rating_seed`, and Glicko-2 fields
- **Faction**: One of 10 BfME factions (Gondor, Rohan, Mordor, etc.) with a `color`, `good` boolean, `heroes` array, and `bases` array
- **Appearance**: Join table linking Player + Faction + Match, storing `hero_kills`, `unit_kills`, `elo_rating`, `elo_rating_change`, and ignore flags
- **Wc3statsReplay**: Stores raw replay data from wc3stats.com API with parsed metadata

Key relationships:
- Match `has_many :appearances` and `has_many :players, through: :appearances`
- Match `belongs_to :wc3stats_replay` (optional)
- Player `has_many :appearances` and `has_many :matches, through: :appearances`
- Appearance `belongs_to :player, :faction, :match`

## Important: uploaded_at vs playedOn

The `uploaded_at` field on Match represents when the replay was **first uploaded** to wc3stats.com, NOT when the game was played. The wc3stats API field `playedOn` is misleadingly named - it's actually the upload timestamp.

- `Wc3statsReplay#played_at` returns the **earliest** upload timestamp from all uploads (a replay can be uploaded multiple times by different players)
- This is used for chronological ordering of matches for ELO/Glicko-2 calculations
- The `Match.chronological` scope orders by: major_version, build_version, row_order, map_version, uploaded_at, wc3stats_replay_id

## Rating Systems

### ELO Rating
- Managed by `EloRecalculator` service (app/services/elo_recalculator.rb)
- K-factor: 32
- Team-based: compares player rating against average opponent team rating
- Recalculates ALL matches from scratch when called (resets to seed values first)

### Glicko-2 Rating
- Managed by `Glicko2Recalculator` service (app/services/glicko2_recalculator.rb)
- More sophisticated rating with rating deviation and volatility
- Also recalculates from scratch

### Custom Rating (CR)
- Managed by `CustomRatingRecalculator` service (app/services/custom_rating_recalculator.rb)
- Default rating: 1300
- Variable K-factor: 40 (new player < 30 games), 30 (normal), 20 (1800+ or reached 2000)
- Effective rating: 20% individual + 80% team average vs opponent team average
- New player bonus: First 20 wins get decreasing bonus points (20, 19, 18... 1)

**Contribution bonus system:**
Players are ranked within their team by performance score (calculated from hero kill %, unit kill %, castle raze %, and team heal % contributions - same as ML score but without the rating component).

- **Both teams** (net 0 points distributed):
  - 1st place: +1
  - 2nd place: +1
  - 3rd place: 0
  - 4th place: -1
  - 5th place: -1

### When Ratings are Recalculated
- On match create (MatchesController#create)
- On match update (MatchesController#update)
- Via rake task: `bin/rails wc3stats:sync`

### ML Score
- Stored on Player model as `ml_score` (0-100 scale, 50 = average)
- Computed by `MlScoreRecalculator` service using logistic regression weights
- Weights are learned from historical match data by `PredictionModelTrainer`
- Stored in `PredictionWeight` model, retrained every 20 new matches

**Features used:**
- Custom Rating (CR) relative to 1300 baseline
- Hero kill contribution % (player's share of team hero kills)
- Unit kill contribution % (player's share of team unit kills)
- Castle raze contribution % (player's share of team castles razed)
- Team heal contribution % (player's share of team healing to teammates)
- Hero uptime % (percentage of match time heroes are alive)

**Confidence adjustment:**
Players with few games have their score pulled toward 50 to prevent inflated scores from small sample sizes:
```
confidence = 1 - e^(-games_played / 10)
final_score = 50 + (raw_score - 50) * confidence
```
- 1 game: ~10% confidence (score ≈ 50)
- 10 games: ~63% confidence
- 20 games: ~86% confidence
- 50+ games: ~99% confidence (full score)

**Lobby prediction:**
`LobbyScorePredictor` uses the same weights to predict match outcomes by comparing team averages. Shows win probability for Good vs Evil teams.

**New player defaults:**
When adding an unknown player to a lobby (via "New Player" option), the defaults are:
- Custom Rating: 1300
- Glicko-2: 1200
- ML Score: 35

These values are defined in `NewPlayerDefaults` model.

## Match Chronological Ordering

Matches are ordered for rating calculations using multiple criteria (see `Match.chronological` scope):
1. WC3 game version (`major_version`, `build_version`)
2. Manual `row_order` (for fine-tuning order of same-day matches)
3. Map version (parsed from filename, e.g., "4.5e")
4. `uploaded_at` (earliest upload timestamp)
5. `wc3stats_replay_id` (fallback)

## Map Version Parsing

`Wc3statsReplay#map_version` parses version from map filename:
- `BFME4.5e.w3x` → `"4.5e"`
- `BFME4.3gObs.w3x` → `"4.3gObs"`
- `BFME3.8Beta3.w3x` → `"3.8Beta3"`
- Only `.w3x` files are parsed (`.w3m` files return nil)

Test maps (containing "test" in filename) are automatically marked as `ignored: true`.

## Statistics Calculators

- **PlayerStatsCalculator**: Calculates per-player stats (wins, losses, top hero killer, etc.)
- **FactionStatsCalculator**: Calculates per-faction stats across all players, supports optional `map_version` filter
- **FactionEventStatsCalculator**: Calculates event-based stats from replay data (hero uptime, base uptime, hero K/D), supports optional `map_version` filter

Stats handle ties by sharing credit (e.g., if 2 players tie for top hero killer, each gets 0.5).

The faction show page includes a map version dropdown to filter stats by specific game versions (e.g., "4.5e").

## Stats Caching

Stats are cached using `StatsCacheKey` to avoid recalculating on every page load:

- **Cache key** is based on `Match.maximum(:updated_at)`, `Match.count`, and `Appearance.maximum(:updated_at)`
- **Auto-invalidation**: Cache invalidates automatically when matches or appearances are updated
- **Manual invalidation**: Run `bin/rails runner "StatsCacheKey.invalidate!"` to force cache refresh
- **Deploy invalidation**: The `.kamal/hooks/post-deploy` hook automatically invalidates cache after each deploy

**Cached pages include:**
- Home page (stats cards, recent lobby/match)
- Matches index (paginated, per-user admin status)
- Match show (individual match details)
- Faction show (stats filtered by optional `map_version` parameter)

**When to invalidate cache:**
- After running backfill migrations that update appearance data
- After deploying code that changes how stats are calculated
- After any manual data fixes

Note: Kamal deploys automatically invalidate cache via the post-deploy hook.

## Authentication & Authorization

- **Devise** for user authentication
- **CanCanCan** for authorization (app/models/ability.rb)
- Two user roles defined in User::ROLES: `admin` (full access) and `uploader` (limited access)
- Only admins can manage all resources via `can :manage, :all`

## WC3Stats Integration

### Importing Replays
```bash
bin/rails wc3stats:sync              # Full sync: import, build matches, fix data, recalculate ratings
bin/rails wc3stats:import            # Import replays only
bin/rails wc3stats:import_recent     # Import last 50 replays
```

### Data Fixing Tasks
```bash
bin/rails wc3stats:fix_uploaded_at   # Fix uploaded_at to use earliest upload timestamp
bin/rails wc3stats:backfill_ordering # Backfill version and date fields
bin/rails wc3stats:set_ignore_kills  # Set ignore flags on zero-kill appearances
```

## URL Routing

Matches use checksums instead of IDs in URLs for SEO-friendly links:
- `Match#to_param` returns the replay hash (checksum)
- `Match.find_by_checksum_or_id` handles lookup by either checksum or ID
- Example: `/matches/abc123def456` instead of `/matches/42`

## Production Server

The application is deployed at **https://bfme.snaps.games**

When making database changes (migrations), remember to also apply them to production:
```bash
# After creating a migration locally, deploy and run:
bin/rails db:migrate RAILS_ENV=production
```

Any data-fixing rake tasks should also be run on production after deployment:
```bash
bin/rails wc3stats:fix_uploaded_at RAILS_ENV=production
bin/rails wc3stats:sync RAILS_ENV=production
```

## Backfill Migrations

**IMPORTANT:** When adding new columns that need data populated from existing replay data, always create a backfill migration instead of relying on manual rake tasks.

**Why migrations over rake tasks:**
- Migrations run automatically on deploy (`bin/rails db:migrate`)
- Migrations are tracked and won't run twice
- Rake tasks require manual intervention and can be forgotten
- Both dev and production servers need the same data

**Example backfill migration pattern:**
```ruby
class BackfillNewColumnFromReplayData < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    Appearance.joins(match: :wc3stats_replay)
      .includes({ match: :wc3stats_replay }, :player)
      .find_each do |appearance|
      # Extract data from replay and update appearance
    end
  end

  def down
    # No-op: don't remove data on rollback
  end
end
```

**After deploy**, remember to:
1. Run `bin/rails db:migrate` (runs backfill migrations)
2. Run `bin/rails runner "StatsCacheKey.invalidate!"` (refresh cached stats)

## Development Commands

### Setup
```bash
bin/setup          # Initial setup: bundle install, db setup, etc.
bin/rails db:seed  # Seed factions and test data
```

### Server
```bash
bin/dev            # Start development server with all services
bin/rails server   # Start Rails server only
```

### Database
```bash
bin/rails db:migrate                    # Run pending migrations
bin/rails db:rollback                   # Rollback last migration
bin/rails db:schema:load                # Load schema from db/schema.rb
bin/rails db:reset                      # Drop, create, load schema, and seed
```

### Testing
```bash
bin/rails test                                      # Run all tests
bin/rails test test/models/player_test.rb           # Run single test file
bin/rails test test/models/player_test.rb:15        # Run single test at line
```

### Code Quality
```bash
bin/rubocop        # Ruby style linter (rails-omakase)
bin/brakeman       # Security vulnerability scanner
bin/bundler-audit  # Check gems for known vulnerabilities
bin/ci             # Run full CI suite
```

## Technology Stack

- **Rails 8.1** with Hotwire (Turbo + Stimulus)
- **SQLite3** database
- **Tailwind CSS 4.4** for styling
- **Simple Form** for form helpers
- **Devise** for authentication
- **CanCanCan** for authorization
- **chronic_duration** gem for parsing duration strings (e.g., "45m" → 2700 seconds)
- **Solid Queue/Cache/Cable** for background jobs, caching, and WebSocket connections

## Key Implementation Details

### Match Form Architecture

The match form uses nested attributes (app/views/matches/_form.html.erb and _form_appearances.html.erb):
- Creates 10 appearance fields (one per faction) on match creation
- Appearances are pre-built in `MatchesController#new` via `Faction.all.each { |faction| @match.appearances.build(faction: faction) }`
- Manual nested attributes handling in create/update actions instead of using strong params

### Duration Input

Match duration accepts human-readable strings via chronic_duration gem:
- Controller converts string to seconds: `ChronicDuration.parse(params[:match][:seconds])`
- Supports formats like "1h 30m", "45 minutes", "90m", etc.

### Previous W-L Record Display

Match show page displays each player's W-L record before that match:
- `MatchesHelper#previous_record_for_appearance` calculates wins/losses
- `MatchesHelper#match_is_before?` compares matches using chronological ordering criteria
- Displayed as green wins / red losses (e.g., "5W-3L")

## File Structure

- `app/controllers/*_controller.rb` - Standard Rails CRUD controllers
- `app/models/*.rb` - ActiveRecord models with minimal business logic
- `app/services/*.rb` - Service objects for complex operations (calculators, recalculators, importers)
- `app/helpers/*.rb` - View helpers for display logic
- `app/views/matches/` - Complex nested forms for match entry
- `lib/tasks/wc3stats.rake` - Rake tasks for data import and sync
- `test/fixtures/*.yml` - Test data fixtures
- `config/routes.rb` - RESTful routes for all resources

## Common Issues and Solutions

### Matches appear out of order (KNOWN LIMITATION)

**This is a fundamental limitation of the wc3stats.com data we import from.**

The wc3stats API has several quirks that make accurate chronological ordering difficult:

1. **`playedOn` is actually upload date** - The API field is misleadingly named; it's when the replay was uploaded, not when the game was played. We store this as `uploaded_at`.

2. **Single uploads: IDs are in order** - When someone uploads replays one at a time, the `wc3stats_replay_id` values are chronologically correct.

3. **Batch uploads: IDs are in REVERSE order** - When someone uploads multiple replays at once, they get assigned IDs in reverse chronological order (oldest game gets highest ID).

**Current mitigations:**
- We use `uploaded_at` with the **earliest** upload timestamp (replays can be uploaded multiple times)
- We order by game version (`major_version`, `build_version`) first
- We order by map version (e.g., "4.5e") to group patches together
- Manual `row_order` field allows fine-tuning specific matches
- `wc3stats_replay_id` is used as final tiebreaker

**To manually fix ordering:**
- Set `row_order` on matches that need adjustment (lower = earlier)
- Run `wc3stats:sync` to recalculate ratings with new order

**There is no perfect solution** without the actual game timestamps, which wc3stats doesn't provide.

### ELO ratings seem wrong after changes
- Ratings are recalculated from scratch on each match create/update
- Run `wc3stats:sync` to fully recalculate all ratings

### Test maps showing in stats
- Test maps should have `ignored: true` set automatically
- Check `Wc3statsReplay#test_map?` detection

## Testing

Uses Rails default Minitest framework:
- Model tests in `test/models/`
- Controller tests in `test/controllers/`
- Service tests in `test/services/`
- System tests with Capybara + Selenium
- Fixtures in `test/fixtures/`
