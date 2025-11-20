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
end
