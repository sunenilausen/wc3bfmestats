# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Rails 8.1 application for tracking Warcraft 3 Battle for Middle Earth (BfME) match statistics with ELO and Glicko-2 rating systems. Players compete as Good vs Evil factions, and the system calculates and tracks ratings based on match outcomes.

## Core Domain Model

The application uses a join-table architecture for many-to-many relationships:

- **Match**: Represents a game with `played_at` (game time from replay filename), `uploaded_at` (earliest wc3stats upload date), `seconds` (duration), `good_victory` (boolean), `is_draw` (boolean), and ordering fields (`major_version`, `build_version`, `map_version`, `row_order`)
- **Player**: Battle.net user with `nickname`, `battletag`, `elo_rating`, `elo_rating_seed`, and Glicko-2 fields
- **Faction**: One of 10 BfME factions (Gondor, Rohan, Mordor, etc.) with a `color`, `good` boolean, `heroes` array, and `bases` array
- **Appearance**: Join table linking Player + Faction + Match, storing `hero_kills`, `unit_kills`, `elo_rating`, `elo_rating_change`, and ignore flags
- **Wc3statsReplay**: Stores raw replay data from wc3stats.com API with parsed metadata

Key relationships:
- Match `has_many :appearances` and `has_many :players, through: :appearances`
- Match `belongs_to :wc3stats_replay` (optional)
- Player `has_many :appearances` and `has_many :matches, through: :appearances`
- Appearance `belongs_to :player, :faction, :match`

## Important: played_at vs uploaded_at

The Match model has two timestamp fields:
- `played_at` - When the game was **actually played** (parsed from replay filename `Replay_YYYY_MM_DD_HHMM.w3g`)
- `uploaded_at` - When the replay was **first uploaded** to wc3stats.com (earliest upload timestamp)

**Data sources:**
- `Wc3statsReplay#played_at` - Parses the replay filename first (e.g., `Replay_2025_10_19_1942.w3g` → Oct 19, 2025 19:42), falls back to earliest upload timestamp if filename not available
- `Wc3statsReplay#earliest_upload_at` - The earliest upload timestamp from all uploads (a replay can be uploaded multiple times by different players)
- The wc3stats API field `playedOn` is misleadingly named - it's actually the LATEST upload timestamp, not when the game was played

**Chronological ordering:**
- The `Match.chronological` scope orders by: played_at (MOST IMPORTANT), major_version, build_version, row_order, map_version, uploaded_at, wc3stats_replay_id
- `played_at` from replay filename is the most accurate indicator of when games were played
- `uploaded_at` serves as a fallback when filename parsing isn't available

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
- New player bonus: First 15 wins get decreasing bonus points (30, 28, 26... 2), scaled by distance from 1500 rating (full bonus at 1300, 50% at 1400, 0% at 1500+)

**Match experience factor:**
Rating changes are reduced when new players are in the match to protect established players from volatile new player ratings:
- Each player's experience = min(games_played / 30, 1.0)
- Match experience = average of all 10 players' experience
- Base rating change is multiplied by match experience factor

Examples:
- 10 veterans (30+ games): 100% rating change
- 8 veterans + 2 new players (0 games): ~87% rating change
- 5 veterans + 5 brand new players: ~50% rating change

Note: New player bonuses and contribution bonuses are NOT affected by this factor.

**Contribution bonus system:**
Players are ranked within their team by performance score. The performance score uses these weights (all contribution stats capped at stated max):

| Stat | Weight | Max |
|------|--------|-----|
| Hero kills % | 0.25 | 20% per kill (max 40%) |
| Unit kills % | 0.20 | 40% |
| Castle raze % | 0.20 | 30% |
| Hero uptime | 0.20 | - |
| Team heal % | 0.15 | 40% |

Note: Hero kill contribution is capped at 20% per hero killed **only for performance score calculation** (used for contribution bonuses). For example, killing 1 hero caps your performance score contribution at 20% regardless of how many total hero kills your team has. However, player stats display shows the raw (uncapped) percentages.

**Isengard adjustments (contribution ranking only):**
- Castle raze: -1 castle for Isengard in ALL map versions (Grond naturally razes castles). Both player and team totals are reduced by 1.
- Main base destroyed: -1 base for Isengard in map version 4.6+ only. Both player and team totals are reduced by 1.
- These adjustments apply ONLY to the `CustomRatingRecalculator#performance_score` method (which determines contribution ranking and bonus points). They do NOT apply to PERF score (`MlScoreRecalculator`) or faction stats (`PlayerFactionStatsCalculator`).

- **Winning team** (net +3 points distributed):
  - 1st place: +2
  - 2nd place: +1
  - 3rd place: +1
  - 4th place: 0
  - 5th place: -1

- **Losing team** (net 0 points distributed):
  - 1st place: +1
  - 2nd place: +1
  - 3rd place: 0
  - 4th place: -1
  - 5th place: -1

- **MVP bonus** (winning team only): +1 for having both top unit kills AND top hero kills on team (shown as ★)
  - Minas Morgul and Fellowship get their unit kills multiplied by 1.5x for MVP calculation (support faction adjustment)

- **Ring Drop bonus** (Fellowship only): +1 for triggering the Ring Drop event (destroying the ring)
  - **Ring Powered bonus**: Additional +1 if at least 2 of the 3 main Evil bases (Barad-Dur, Morannon, Minas Morgul) are alive at ring drop time (tooltip shows "+2, 2+ evil bases alive")

### When Ratings are Recalculated
- On match create (MatchesController#create)
- On match update (MatchesController#update)
- Via rake task: `bin/rails wc3stats:sync`

### Draws

When players type `-draw` in game, the match ends as a draw. Draw handling:

- **Detection:** `Wc3statsReplay#is_draw?` checks if any player has `"drawer"` in their flags array
- **Match field:** `is_draw` boolean on Match model (default false)
- **Rating impact:** Zero rating change for all players in draw matches
- **Games count:** Draws still increment `custom_rating_games_played`
- **UI display:** Shows "Draw" badge and "(Draw)" instead of Victory/Defeat
- **Prediction accuracy:** Draws show "(draw)" instead of correct/upset

### Performance Score (PERF / ml_score)

The Performance Score measures a player's average contribution to their team, independent of wins/losses or CR. Stored on Player model as `ml_score` using a **0-centered scale** where 0 = average.

**Key concept:** A score of 0 means average contribution (20% of team stats in a 5-player team). Positive = above average contributor, negative = below average.

**Display format:**
- Positive scores show with `+` prefix: `+5.2`
- Negative scores show with `-` prefix: `-3.1`
- Color coding: green (≥ +5), red (≤ -5), gray (between)

**How it's calculated:**
The score is based on deviation from the expected 20% team contribution:

| Stat | Weight | Baseline | Cap |
|------|--------|----------|-----|
| Hero kill contribution % | 0.06 | 20% | 10% per kill |
| Unit kill contribution % | 0.04 | 20% | None |
| Castle raze contribution % | 0.02 | 20% | 20% per castle |
| Team heal contribution % | 0.01 | 20% | 40% per game |
| Hero uptime % | 0.01 | 80% | None |

```
raw_score = Σ(weight × (actual% - baseline%))
sigmoid_score = sigmoid(raw_score × 0.5) × 100 - 50  # Center on 0
final_score = sigmoid_score - average_of_all_scores  # Normalize so avg = 0
```

**Examples:**
- Player with 20% of all team stats → score ≈ 0 (average)
- Player with 30% hero kills, 25% unit kills → score > 0 (above average, e.g., +8)
- Player with 10% unit kills, 0% hero kills → score < 0 (below average, e.g., -12)

**No confidence adjustment:** The raw score is used directly. A player with 1 terrible game will show their actual poor performance, not be pulled toward 0.

Managed by `MlScoreRecalculator` service.

### Faction Performance Score (faction_score)

Similar to overall Performance Score but calculated per-faction. Stored on `PlayerFactionStat` model. Uses the same 0-centered scale and calculation method, but only considers games played with that specific faction.

**Requirements:** Only calculated for players with 10+ games on that faction.

**Display:** Shown in the "F.Perf" column on player faction stats tables.

Managed by `PlayerFactionStatsCalculator` service.

### CR+ Prediction System (Lobby Win Prediction)

CR+ combines Custom Rating (CR) with Performance Score to predict match outcomes. For new players with poor performance, their effective CR is penalized. Managed by `LobbyWinPredictor` service.

**Formula:**
```
# For players with 30+ games: just use CR
effective_cr = cr

# For players with <30 games AND PERF < 0 (below average):
ml_deviation = perf_score - 0  # Now 0-centered
adjustment = (ml_deviation / 50) × 200 × (1 - games / 30)
effective_cr = cr + adjustment  # adjustment is negative

# For players with <30 games AND PERF >= 0: NO bonus, use CR directly
effective_cr = cr
```

**Key behavior:**
- **Experienced players (30+ games):** Uses CR directly, no adjustment
- **New players with PERF ≥ 0:** No bonus - trust their CR (good performers don't need help)
- **New players with PERF < 0:** Penalty scales down as they play more games

**Examples (with 0-centered PERF):**
- New player (0 games), PERF +20: no adjustment (trust CR)
- New player (0 games), PERF -20: -80 CR penalty
- Player (15 games), PERF -20: -40 CR penalty (half, since 15/30 games)
- Player (30+ games), any PERF: no adjustment

**Win probability calculation:**
```
good_win_prob = 1 / (1 + exp(-cr_diff / 150))
```
Where `cr_diff = good_avg_effective_cr - evil_avg_effective_cr`

**Constants:**
- `GAMES_FOR_FULL_CR_TRUST = 30`
- `MAX_ML_CR_ADJUSTMENT = 200`
- `ML_BASELINE = 0` (average performance, 0-centered)

**Faction Impact Weights:**

Each player's effective CR is multiplied by their faction's impact weight before averaging into the team score. This reflects that some factions are more impactful (carry) than others (support).

| Faction | Weight | Effect |
|---------|--------|--------|
| Mordor | 1.08 | +8% CR contribution |
| Gondor | 1.05 | +5% CR contribution |
| Easterlings | 0.99 | -1% CR contribution |
| Harad | 0.98 | -2% CR contribution |
| Isengard | 0.99 | -1% CR contribution |
| Minas Morgul | 0.96 | -4% CR contribution |
| Fellowship | 0.96 | -4% CR contribution |
| Rohan | 1.00 | Neutral |
| Dol Amroth | 0.99 | -1% CR contribution |
| Fangorn | 1.00 | Neutral |

Team weight sums are balanced: Good = 5.00, Evil = 5.00.

Note: These weights only affect the prediction formula, not the actual CR rating changes.

```
weighted_effective_cr = effective_cr × faction_impact_weight
team_avg = sum(weighted_effective_crs) / team_size
```

Defined in `LobbyWinPredictor::FACTION_IMPACT_WEIGHTS`.

The same formula is used in:
- `LobbyWinPredictor` - for lobby predictions
- `LobbyBalancer` - for auto-balancing teams
- `CustomRatingRecalculator#store_match_prediction` - stores prediction on Match model

**Prediction accuracy note:**
Analysis shows the PERF-based penalty provides minimal predictive value:
- Only changes prediction ~5% of the time
- When it does flip the prediction, it's 50/50 correct/wrong
- Low PERF new players actually have similar or higher win rates than high PERF new players

The penalty is kept for conservative estimation but CR-only would perform equally well.

**New player defaults:**
When adding an unknown player to a lobby (via "New Player" option), the defaults are:
- Custom Rating: 1300
- Glicko-2: 1200
- Performance Score: -15 (below average, conservative estimate for 0-centered scale)

These values are defined in `NewPlayerDefaults` model.

### Stay/Leave Tracking

Players have stay/leave percentages tracked based on replay data. Managed by `StayLeaveRecalculator` service.

**Player fields:**
- `stay_pct` - Percentage of games where player stayed or leave was excused (default 100%)
- `leave_pct` - Percentage of games where player had a real early leave (default 0%)
- `games_stayed` - Count of games stayed (includes excused leaves)
- `games_left` - Count of real early leaves

**Appearance field:**
- `stay_pct` - How long the player stayed in this specific match (from replay `stayPercent`)

**Logic for counting a "real leave":**
A leave only counts if ALL of these are true:
1. Player left before 90% of the game ended
2. Player was the FIRST to leave (no one left before them)
3. No teammate left within 60 seconds after them

This means leaves are "excused" if:
- Someone else left first (game was already ruined)
- A teammate quickly followed (coordinated surrender/disconnect)

**Data source:**
- `leftAt` field in replay JSON (`body.data.game.players[].leftAt`)
- `stayPercent` field for appearance-level stay percentage

**Displayed on:**
- Player show page in the "Player Info" section
- Green color for stay rate ≥95%, red for <80%

**Recalculation:**
- Included in `wc3stats:sync` task (Step 14)
- Included in `wc3stats:recalculate` task (Step 6)
- Included in `Wc3statsSyncJob` (runs after match sync via UI button)
- Included in `RatingRecalculationJob` (runs after manual match create/update)
- Manual: `StayLeaveRecalculator.new.call`

## Match Chronological Ordering

Matches are ordered for rating calculations using multiple criteria (see `Match.chronological` scope):
1. `played_at` - Game time from replay filename (MOST IMPORTANT)
2. WC3 game version (`major_version`, `build_version`)
3. Manual `row_order` (for fine-tuning order of same-day matches)
4. Map version (parsed from filename, e.g., "4.5e")
5. `uploaded_at` (earliest upload timestamp, fallback)
6. `wc3stats_replay_id` (final fallback)

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

### Player Average Stats Contribution Caps

When calculating player average contribution percentages (displayed on player stats page), contributions are capped per game to prevent outliers from skewing averages:

| Stat | Cap per game |
|------|--------------|
| Hero kill contribution | 10% per hero killed |
| Castle raze contribution | 20% per castle razed |
| Team heal contribution | 40% flat cap |
| Unit kill contribution | No cap |

**Examples:**
- Player kills 1 hero when team has 2 total: raw 50% → capped to 10% (1 kill × 10%)
- Player razes 1 castle when team has 2 total: raw 50% → capped to 20% (1 castle × 20%)
- Player does 80% of team healing: capped to 40%

These same caps are applied when calculating Performance Score (ml_score) and Faction Score.

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

The application is deployed at **https://bfme.snaps.games** on server `157.90.158.244`.

### Clone Production Database to Local

```bash
scp root@157.90.158.244:/var/lib/docker/volumes/wc3bfmestats_storage/_data/production.sqlite3 ./storage/development.sqlite3
```

### Database Migrations

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
