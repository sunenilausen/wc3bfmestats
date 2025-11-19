# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Rails 8.1 application for tracking Warcraft 3 Battle for Middle Earth (BfME) match statistics with an ELO rating system. Players compete as Good vs Evil factions, and the system calculates and tracks ELO ratings based on match outcomes.

## Core Domain Model

The application uses a join-table architecture for many-to-many relationships:

- **Match**: Represents a game with `played_at`, `seconds` (duration), and `good_victory` (boolean)
- **Player**: Battle.net user with `nickname`, `battletag`, `elo_rating`, and `elo_rating_seed`
- **Faction**: One of 10 BfME factions (Gondor, Rohan, Mordor, etc.) with a `color` and `good` boolean
- **Appearance**: Join table linking Player + Faction + Match, storing `hero_kills`, `unit_kills`, `elo_rating`, and `elo_rating_change`

Key relationships:
- Match `has_many :appearances` and `has_many :players, through: :appearances`
- Player `has_many :appearances` and `has_many :matches, through: :appearances`
- Appearance `belongs_to :player, :faction, :match`

## ELO Rating System

The core rating logic is in `MatchesController#calculate_and_update_elo_ratings` (app/controllers/matches_controller.rb:126-146):

- K-factor: 32
- Expected score calculation uses standard ELO formula with 400-point scaling
- Team-based: compares player rating against average opponent team rating
- Ratings are calculated and persisted after match creation/update
- Each appearance stores both the rating at match time and the change amount

## Authentication & Authorization

- **Devise** for user authentication
- **CanCanCan** for authorization (app/models/ability.rb)
- Two user roles defined in User::ROLES: `admin` (full access) and `uploader` (limited access)
- Only admins can manage all resources via `can :manage, :all`

## Quick Import Feature

The matches controller supports a `quickimport_json` parameter for bulk match entry (app/controllers/matches_controller.rb:94-123):

Expected JSON format:
```json
[
  { "Player": "Snaps", "Hero Kills": 2, "Unit Kills": 83 },
  { "Player": "OtherPlayer#1234", "Hero Kills": 5, "Unit Kills": 120 }
]
```

- Automatically creates players if they don't exist (default 1500 ELO)
- Strips battletag numbers from nicknames
- Maps to appearances by array index

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
script/import_players.rb                # Custom player import script
```

### Testing
```bash
bin/rails test                          # Run all tests
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

## File Structure

- `app/controllers/*_controller.rb` - Standard Rails CRUD controllers
- `app/models/*.rb` - ActiveRecord models with minimal business logic
- `app/views/matches/` - Complex nested forms for match entry
- `test/fixtures/*.yml` - Test data fixtures
- `config/routes.rb` - RESTful routes for all resources
- `script/` - Custom utility scripts (e.g., import_players.rb)

## Testing

Uses Rails default Minitest framework:
- Model tests in `test/models/`
- Controller tests in `test/controllers/`
- System tests with Capybara + Selenium
- Fixtures in `test/fixtures/`
