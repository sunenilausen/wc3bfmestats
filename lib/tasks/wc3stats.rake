namespace :wc3stats do
  desc "Import replays from wc3stats.com"
  task import: :environment do
    # Configuration from environment variables
    search_term = ENV.fetch("SEARCH", "BFME")
    limit = ENV["LIMIT"]&.to_i
    max_pages = ENV["MAX_PAGES"]&.to_i
    delay = ENV.fetch("DELAY", "1").to_f

    puts "=" * 60
    puts "WC3Stats Replay Importer"
    puts "=" * 60
    puts "Search term: #{search_term}"
    puts "Limit: #{limit || 'None (fetch all)'}"
    puts "Max pages: #{max_pages || 'None (fetch all)'}"
    puts "Delay between imports: #{delay}s"
    puts "=" * 60
    puts

    # Step 1: Fetch replay IDs
    puts "🔍 Fetching replay IDs from wc3stats.com..."
    puts "This may take a few minutes...\n"

    games_fetcher = Wc3stats::GamesFetcher.new(
      search_term: search_term,
      limit: limit,
      max_pages: max_pages
    )

    replay_ids = games_fetcher.call

    if games_fetcher.errors.any?
      puts "⚠️  Errors during fetch:"
      games_fetcher.errors.each { |error| puts "  - #{error}" }
      puts
    end

    if replay_ids.empty?
      puts "No replay IDs found. Exiting."
      exit
    end

    puts "✓ Found #{replay_ids.count} replay IDs\n\n"

    # Step 2: Filter out already imported replays
    existing_ids = Wc3statsReplay.where(wc3stats_replay_id: replay_ids).pluck(:wc3stats_replay_id)
    new_replay_ids = replay_ids - existing_ids

    puts "📊 Status:"
    puts "  Total found: #{replay_ids.count}"
    puts "  Already imported: #{existing_ids.count}"
    puts "  New to import: #{new_replay_ids.count}"
    puts

    if new_replay_ids.empty?
      puts "✓ All replays already imported!"
      exit
    end

    # Step 3: Import each new replay
    puts "=" * 60
    puts "Starting import of #{new_replay_ids.count} replays..."
    puts "=" * 60
    puts

    imported_count = 0
    failed_count = 0
    errors = []

    new_replay_ids.each_with_index do |replay_id, index|
      progress = "[#{index + 1}/#{new_replay_ids.count}]"
      print "#{progress} Importing replay #{replay_id}... "

      replay_fetcher = Wc3stats::ReplayFetcher.new(replay_id)
      replay = replay_fetcher.call

      if replay
        imported_count += 1
        game_name = replay.game_name || "Unknown"
        players_count = replay.players.count
        puts "✓ #{game_name} (#{players_count} players)"
      else
        failed_count += 1
        error_msg = replay_fetcher.errors.first || "Unknown error"
        puts "✗ #{error_msg}"
        errors << { id: replay_id, error: error_msg }
      end

      # Be respectful to the server
      sleep delay if index < new_replay_ids.count - 1
    end

    # Step 4: Summary
    puts
    puts "=" * 60
    puts "Import Summary"
    puts "=" * 60
    puts "✓ Successfully imported: #{imported_count}"
    puts "✗ Failed: #{failed_count}"
    puts "=" * 60

    if errors.any?
      puts
      puts "Failed replays:"
      errors.each do |error|
        puts "  - Replay #{error[:id]}: #{error[:error]}"
      end
    end

    puts
    puts "Total replays in database: #{Wc3statsReplay.count}"
  end

  desc "Import recent replays (last 50 by default)"
  task import_recent: :environment do
    ENV["LIMIT"] ||= "50"
    Rake::Task["wc3stats:import"].invoke
  end

  desc "Show import statistics"
  task stats: :environment do
    total = Wc3statsReplay.count

    if total.zero?
      puts "No replays imported yet."
      exit
    end

    puts "=" * 60
    puts "WC3Stats Database Statistics"
    puts "=" * 60
    puts "Total replays: #{total}"
    puts

    # Group by map
    replays_by_map = Wc3statsReplay.all.group_by(&:map_name)
    puts "Replays by map:"
    replays_by_map.sort_by { |_map, replays| -replays.count }.each do |map, replays|
      puts "  #{map}: #{replays.count}"
    end

    puts
    puts "Most recent replay:"
    latest = Wc3statsReplay.order(created_at: :desc).first
    if latest
      puts "  #{latest.game_name} (ID: #{latest.wc3stats_replay_id})"
      puts "  Played: #{latest.played_at&.strftime('%Y-%m-%d %H:%M')}"
      puts "  Imported: #{latest.created_at.strftime('%Y-%m-%d %H:%M')}"
    end
    puts "=" * 60
  end

  desc "Full sync: import/update replays, build matches, cleanup invalid, recalculate ELO"
  task sync: :environment do
    search_term = ENV.fetch("SEARCH", "BFME")
    limit = ENV["LIMIT"]&.to_i
    max_pages = ENV["MAX_PAGES"]&.to_i
    delay = ENV.fetch("DELAY", "0.5").to_f
    force_update = ENV["FORCE"]&.downcase == "true"

    puts "=" * 60
    puts "WC3Stats Full Sync"
    puts "=" * 60
    puts "Search term: #{search_term}"
    puts "Limit: #{limit || 'None (fetch all)'}"
    puts "Max pages: #{max_pages || 'None (fetch all)'}"
    puts "Force update: #{force_update ? 'Yes (re-fetch existing)' : 'No (skip existing)'}"
    puts "=" * 60
    puts

    # Step 1: Fetch replay IDs
    puts "Step 1: Fetching replay IDs from wc3stats.com..."
    games_fetcher = Wc3stats::GamesFetcher.new(
      search_term: search_term,
      limit: limit,
      max_pages: max_pages
    )

    replay_ids = games_fetcher.call

    if games_fetcher.errors.any?
      puts "Errors during fetch:"
      games_fetcher.errors.each { |error| puts "  - #{error}" }
    end

    if replay_ids.empty?
      puts "No replay IDs found. Exiting."
      next
    end

    puts "Found #{replay_ids.count} replay IDs"
    puts

    # Step 2: Import replays
    puts "Step 2: Importing replays..."
    existing_ids = Wc3statsReplay.where(wc3stats_replay_id: replay_ids).pluck(:wc3stats_replay_id)

    if force_update
      ids_to_fetch = replay_ids
      puts "  Force mode: fetching all #{ids_to_fetch.count} replays"
    else
      ids_to_fetch = replay_ids - existing_ids
      puts "  New replays to fetch: #{ids_to_fetch.count}"
      puts "  Already in database (skipped): #{existing_ids.count}"
    end
    puts

    imported_count = 0
    updated_count = 0
    failed_count = 0

    ids_to_fetch.each_with_index do |replay_id, index|
      progress = "[#{index + 1}/#{ids_to_fetch.count}]"
      is_update = existing_ids.include?(replay_id)
      print "#{progress} #{is_update ? 'Updating' : 'Fetching'} replay #{replay_id}... "

      replay_fetcher = Wc3stats::ReplayFetcher.new(replay_id)
      replay = replay_fetcher.call

      if replay
        if is_update
          updated_count += 1
          puts "updated (#{replay.players.count} players)"
        else
          imported_count += 1
          puts "imported (#{replay.players.count} players)"
        end
      else
        failed_count += 1
        puts "failed: #{replay_fetcher.errors.first}"
      end

      sleep delay if index < ids_to_fetch.count - 1
    end

    puts
    puts "Import summary:"
    puts "  New imports: #{imported_count}"
    puts "  Updated: #{updated_count}" if force_update
    puts "  Failed: #{failed_count}"
    puts

    # Step 3: Fix Korean/Unicode name encoding issues
    puts "Step 3: Fixing Korean/Unicode name encoding..."
    unicode_fixer = UnicodeNameFixer.new
    unicode_fixer.call
    if unicode_fixer.fixed_count > 0
      puts "  Fixed #{unicode_fixer.fixed_count} players with encoding issues"
      unicode_fixer.changes.select { |c| c[:type] == :player }.first(5).each do |change|
        puts "    #{change[:nickname][:from]} → #{change[:nickname][:to]}"
      end
      puts "    ..." if unicode_fixer.fixed_count > 5
    else
      puts "  No encoding issues found"
    end
    if unicode_fixer.errors.any?
      puts "  Errors: #{unicode_fixer.errors.count}"
    end
    puts

    # Step 4: Set ignore flags on kill stats
    puts "Step 4: Updating ignore flags on kill stats..."
    updated_unit = 0
    updated_hero = 0

    Match.includes(:appearances).find_each do |match|
      appearances = match.appearances

      appearances.each do |app|
        if app.unit_kills == 0 && !app.ignore_unit_kills?
          app.update_column(:ignore_unit_kills, true)
          updated_unit += 1
        end
      end

      all_zero = appearances.all? { |a| a.hero_kills.nil? || a.hero_kills == 0 }
      if all_zero
        appearances.each do |app|
          unless app.ignore_hero_kills?
            app.update_column(:ignore_hero_kills, true)
            updated_hero += 1
          end
        end
      end
    end

    if updated_unit > 0 || updated_hero > 0
      puts "  Set ignore_unit_kills on #{updated_unit} appearances"
      puts "  Set ignore_hero_kills on #{updated_hero} appearances"
    else
      puts "  No changes needed"
    end
    puts

    # Step 5: Cleanup invalid matches
    puts "Step 5: Cleaning up invalid matches..."
    invalid_matches = Match.left_joins(:appearances)
                           .group(:id)
                           .having("COUNT(appearances.id) != 10")

    invalid_count = invalid_matches.count.size
    if invalid_count > 0
      invalid_matches.find_each(&:destroy)
      puts "  Deleted #{invalid_count} invalid matches"
    else
      puts "  No invalid matches found"
    end
    puts

    # Step 6: Backfill ordering fields for new matches
    puts "Step 6: Backfilling ordering fields..."
    matches_needing_backfill = Match.joins(:wc3stats_replay)
                                    .where(major_version: nil)
                                    .includes(:wc3stats_replay)
    backfill_count = 0

    matches_needing_backfill.find_each do |match|
      replay = match.wc3stats_replay
      changes = {
        major_version: replay.major_version,
        build_version: replay.build_version,
        map_version: replay.map_version
      }.compact

      if changes.any?
        match.update_columns(changes)
        backfill_count += 1
      end
    end

    puts "  Backfilled #{backfill_count} matches"
    puts

    # Step 7: Recalculate ELO
    puts "Step 7: Recalculating ELO ratings..."
    elo_recalculator = EloRecalculator.new
    elo_recalculator.call

    puts "  Matches processed: #{elo_recalculator.matches_processed}"
    if elo_recalculator.errors.any?
      puts "  Errors: #{elo_recalculator.errors.count}"
      elo_recalculator.errors.first(3).each { |e| puts "    - #{e}" }
    end
    puts

    # Step 8: Recalculate Glicko-2
    puts "Step 8: Recalculating Glicko-2 ratings..."
    glicko_recalculator = Glicko2Recalculator.new
    glicko_recalculator.call

    puts "  Matches processed: #{glicko_recalculator.matches_processed}"
    if glicko_recalculator.errors.any?
      puts "  Errors: #{glicko_recalculator.errors.count}"
      glicko_recalculator.errors.first(3).each { |e| puts "    - #{e}" }
    end
    puts

    # Final summary
    puts "=" * 60
    puts "Sync Complete"
    puts "=" * 60
    puts "Replays in database: #{Wc3statsReplay.count}"
    puts "Valid matches: #{Match.count}"
    puts "Players: #{Player.count}"
    puts
    puts "=" * 60
  end

  desc "Set ignore_unit_kills and ignore_hero_kills flags on appearances"
  task set_ignore_kills: :environment do
    puts "=" * 60
    puts "Setting ignore_kills flags on appearances"
    puts "=" * 60
    puts

    updated_unit_kills = 0
    updated_hero_kills = 0

    Match.includes(:appearances).find_each do |match|
      appearances = match.appearances

      # Ignore unit kills when unit_kills is 0
      appearances.each do |app|
        if app.unit_kills == 0 && !app.ignore_unit_kills?
          app.update_column(:ignore_unit_kills, true)
          updated_unit_kills += 1
        end
      end

      # Ignore hero kills when all players in the match have 0 hero kills
      all_zero_hero_kills = appearances.all? { |a| a.hero_kills.nil? || a.hero_kills == 0 }
      if all_zero_hero_kills
        appearances.each do |app|
          unless app.ignore_hero_kills?
            app.update_column(:ignore_hero_kills, true)
            updated_hero_kills += 1
          end
        end
      end
    end

    puts "Updated #{updated_unit_kills} appearances with ignore_unit_kills = true"
    puts "Updated #{updated_hero_kills} appearances with ignore_hero_kills = true"
    puts "=" * 60
  end

  desc "Backfill ordering fields (major_version, build_version, map_version) on existing matches"
  task backfill_ordering: :environment do
    puts "=" * 60
    puts "Backfilling Match Ordering Fields"
    puts "=" * 60
    puts

    matches_with_replay = Match.joins(:wc3stats_replay).includes(:wc3stats_replay)
    total = matches_with_replay.count
    updated = 0
    skipped = 0

    puts "Matches with replays: #{total}"
    puts

    matches_with_replay.find_each.with_index do |match, index|
      replay = match.wc3stats_replay

      major = replay.major_version
      build = replay.build_version
      map_ver = replay.map_version

      # Only update if we have data and it differs
      if major || build || map_ver
        changes = {}
        changes[:major_version] = major if major && match.major_version != major
        changes[:build_version] = build if build && match.build_version != build
        changes[:map_version] = map_ver if map_ver && match.map_version != map_ver

        if changes.any?
          match.update_columns(changes)
          updated += 1
        else
          skipped += 1
        end
      else
        skipped += 1
      end

      print "\r  Progress: #{index + 1}/#{total} (updated: #{updated}, skipped: #{skipped})"
    end

    puts
    puts
    puts "=" * 60
    puts "Summary"
    puts "=" * 60
    puts "  Updated: #{updated}"
    puts "  Skipped: #{skipped}"
    puts "=" * 60
  end
end
