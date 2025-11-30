namespace :wc3stats do
  desc "Import replays from wc3stats.com"
  task import: :environment do
    # Configuration from environment variables
    search_term = ENV.fetch("SEARCH", "BFME")
    limit = ENV["LIMIT"]&.to_i
    delay = ENV.fetch("DELAY", "1").to_f

    puts "=" * 60
    puts "WC3Stats Replay Importer"
    puts "=" * 60
    puts "Search term: #{search_term}"
    puts "Limit: #{limit || 'None (fetch all)'}"
    puts "Delay between imports: #{delay}s"
    puts "=" * 60
    puts

    # Step 1: Fetch replay IDs from API
    puts "Fetching replay IDs from wc3stats.com API..."

    games_fetcher = Wc3stats::GamesFetcher.new(
      search_term: search_term,
      limit: limit
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

    puts "Found #{replay_ids.count} replay IDs\n\n"

    # Step 2: Filter out already imported replays
    existing_ids = Wc3statsReplay.where(wc3stats_replay_id: replay_ids).pluck(:wc3stats_replay_id)
    new_replay_ids = replay_ids - existing_ids

    puts "Status:"
    puts "  Total found: #{replay_ids.count}"
    puts "  Already imported: #{existing_ids.count}"
    puts "  New to import: #{new_replay_ids.count}"
    puts

    if new_replay_ids.empty?
      puts "All replays already imported!"
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
        puts "OK #{game_name} (#{players_count} players)"
      else
        failed_count += 1
        error_msg = replay_fetcher.errors.first || "Unknown error"
        puts "FAILED #{error_msg}"
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
    puts "Successfully imported: #{imported_count}"
    puts "Failed: #{failed_count}"
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
      puts "  Uploaded: #{latest.played_at&.strftime('%Y-%m-%d %H:%M')}"
      puts "  Imported: #{latest.created_at.strftime('%Y-%m-%d %H:%M')}"
    end
    puts "=" * 60
  end

  desc "Full sync: import/update replays, build matches, cleanup invalid, recalculate ratings"
  task sync: :environment do
    search_term = ENV.fetch("SEARCH", "BFME")
    limit = ENV["LIMIT"]&.to_i
    delay = ENV.fetch("DELAY", "0.5").to_f
    force_update = ENV["FORCE"]&.downcase == "true"

    puts "=" * 60
    puts "WC3Stats Full Sync"
    puts "=" * 60
    puts "Search term: #{search_term}"
    puts "Limit: #{limit || 'None (fetch all)'}"
    puts "Force update: #{force_update ? 'Yes (re-fetch existing)' : 'No (skip existing)'}"
    puts "=" * 60
    puts

    # Step 1: Fetch replay IDs from API
    puts "Step 1: Fetching replay IDs from wc3stats.com API..."
    games_fetcher = Wc3stats::GamesFetcher.new(
      search_term: search_term,
      limit: limit
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

    # Step 3: Build matches from replays
    puts "Step 3: Building matches from replays..."
    replays_without_matches = Wc3statsReplay.left_joins(:match).where(matches: { id: nil })
    replays_count = replays_without_matches.count
    matches_created = 0
    matches_failed = 0

    if replays_count > 0
      puts "  Found #{replays_count} replays without matches"
      replays_without_matches.find_each do |replay|
        builder = Wc3stats::MatchBuilder.new(replay)
        if builder.call
          matches_created += 1
        else
          matches_failed += 1
        end
      end
      puts "  Created: #{matches_created} matches"
      puts "  Failed: #{matches_failed}" if matches_failed > 0
    else
      puts "  All replays already have matches"
    end
    puts

    # Step 4: Fix Korean/Unicode name encoding issues
    puts "Step 4: Fixing Korean/Unicode name encoding..."
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

    # Step 5: Set ignore flags on kill stats
    puts "Step 5: Updating ignore flags on kill stats..."
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

    # Step 6: Mark invalid matches as ignored
    puts "Step 6: Marking invalid matches as ignored..."
    invalid_matches = Match.left_joins(:appearances)
                           .where(ignored: false)
                           .group(:id)
                           .having("COUNT(appearances.id) != 10")

    invalid_count = invalid_matches.count.size
    if invalid_count > 0
      invalid_matches.find_each { |m| m.update_column(:ignored, true) }
      puts "  Marked #{invalid_count} invalid matches as ignored"
    else
      puts "  No invalid matches found"
    end
    puts

    # Step 7: Backfill ordering fields and uploaded_at for matches
    puts "Step 7: Backfilling ordering fields..."
    matches_needing_backfill = Match.joins(:wc3stats_replay)
                                    .where("major_version IS NULL OR uploaded_at IS NULL")
                                    .includes(:wc3stats_replay)
    backfill_count = 0

    matches_needing_backfill.find_each do |match|
      replay = match.wc3stats_replay
      changes = {}

      # Backfill version fields if missing
      changes[:major_version] = replay.major_version if match.major_version.nil? && replay.major_version
      changes[:build_version] = replay.build_version if match.build_version.nil? && replay.build_version
      changes[:map_version] = replay.map_version if match.map_version.nil? && replay.map_version

      # Backfill uploaded_at from replay if missing
      changes[:uploaded_at] = replay.played_at if match.uploaded_at.nil? && replay.played_at

      if changes.any?
        match.update_columns(changes)
        backfill_count += 1
      end
    end

    puts "  Backfilled #{backfill_count} matches"
    puts

    # Step 8: Create observer players
    puts "Step 8: Creating observer players..."
    observers_created = 0
    Wc3statsReplay.find_each do |replay|
      replay.players.each do |player_data|
        slot = player_data["slot"]
        next unless slot.nil? || slot > 9 || player_data["isWinner"].nil?

        battletag = player_data["name"]
        next if battletag.blank?

        # Fix encoding
        fixed_battletag = begin
          bytes = battletag.encode("ISO-8859-1", "UTF-8").bytes
          fixed = bytes.pack("C*").force_encoding("UTF-8")
          if fixed.valid_encoding? && fixed != battletag
            fixed
          else
            battletag
          end
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          battletag
        end

        # Create player if not exists
        unless Player.exists?(battletag: fixed_battletag) || Player.exists?(battletag: battletag)
          nickname = fixed_battletag.split("#").first
          Player.create!(
            battletag: fixed_battletag,
            nickname: nickname
          )
          observers_created += 1
        end
      end
    end
    puts "  Created #{observers_created} new observer players"
    puts

    # Step 9: Recalculate Custom Ratings
    puts "Step 9: Recalculating Custom Ratings..."
    custom_rating_recalculator = CustomRatingRecalculator.new
    custom_rating_recalculator.call

    puts "  Matches processed: #{custom_rating_recalculator.matches_processed}"
    if custom_rating_recalculator.errors.any?
      puts "  Errors: #{custom_rating_recalculator.errors.count}"
      custom_rating_recalculator.errors.first(3).each { |e| puts "    - #{e}" }
    end
    puts

    # Step 10: Train prediction model
    puts "Step 10: Training ML prediction model..."
    trainer = PredictionModelTrainer.new
    model = trainer.train
    if model
      puts "  Model trained on #{model.games_trained_on} games"
      puts "  Accuracy: #{model.accuracy}%"
      puts "  Weights:"
      puts "    CR: #{model.elo_weight.round(4)}"
      puts "    Hero K/D: #{model.hero_kd_weight.round(4)}"
      puts "    HK%: #{model.hero_kill_contribution_weight.round(4)}"
      puts "    UK%: #{model.unit_kill_contribution_weight.round(4)}"
      puts "    CK%: #{model.castle_raze_contribution_weight.round(4)}"
      puts "    Enemy CR Diff: #{model.enemy_elo_diff_weight.round(4)}"
      puts "    Games: #{model.games_played_weight.round(4)}"
    else
      puts "  No training data available"
    end
    puts

    # Step 11: Recalculate ML scores for all players
    puts "Step 11: Recalculating ML scores for all players..."
    MlScoreRecalculator.new.call
    puts "  Updated ML scores for #{Player.count} players"
    puts

    # Final summary
    puts "=" * 60
    puts "Sync Complete"
    puts "=" * 60
    puts "Replays in database: #{Wc3statsReplay.count}"
    puts "Valid matches: #{Match.where(ignored: false).count}"
    puts "Ignored matches: #{Match.where(ignored: true).count}"
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

  desc "Backfill ordering fields (major_version, build_version, map_version, uploaded_at) on existing matches"
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
      # replay.played_at returns the earliest upload timestamp
      earliest_upload = replay.played_at

      # Only update if we have data and it differs
      if major || build || map_ver || earliest_upload
        changes = {}
        changes[:major_version] = major if major && match.major_version != major
        changes[:build_version] = build if build && match.build_version != build
        changes[:map_version] = map_ver if map_ver && match.map_version != map_ver
        changes[:uploaded_at] = earliest_upload if earliest_upload && match.uploaded_at != earliest_upload

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

  desc "Fix uploaded_at to use earliest upload timestamp from wc3stats (for correct chronological ordering)"
  task fix_uploaded_at: :environment do
    puts "=" * 60
    puts "Fixing uploaded_at to use earliest upload timestamp"
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
      # replay.played_at returns the earliest upload timestamp from all uploads
      earliest_upload = replay.played_at

      if earliest_upload && match.uploaded_at != earliest_upload
        match.update_column(:uploaded_at, earliest_upload)
        updated += 1
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
    puts "  Already correct: #{skipped}"
    puts "=" * 60
  end

  desc "Train/retrain the ML prediction model"
  task train_prediction_model: :environment do
    puts "=" * 60
    puts "Training ML Prediction Model"
    puts "=" * 60
    puts

    puts "Analyzing #{Match.where(ignored: false).count} matches..."
    puts

    trainer = PredictionModelTrainer.new
    model = trainer.train

    if model
      puts "Model trained successfully!"
      puts
      puts "Results:"
      puts "  Games trained on: #{model.games_trained_on}"
      puts "  Accuracy: #{model.accuracy}%"
      puts
      puts "Learned weights:"
      puts "  CR:            #{model.elo_weight.round(6)}"
      puts "  Hero K/D:      #{model.hero_kd_weight.round(6)}"
      puts "  HK%:           #{model.hero_kill_contribution_weight.round(6)}"
      puts "  UK%:           #{model.unit_kill_contribution_weight.round(6)}"
      puts "  CK%:           #{model.castle_raze_contribution_weight.round(6)}"
      puts "  Enemy CR Diff: #{model.enemy_elo_diff_weight.round(6)}"
      puts "  Games Played:  #{model.games_played_weight.round(6)}"
      puts "  Bias:          #{model.bias.round(6)}"
      puts
      puts "=" * 60

      # Show comparison with previous model
      previous = PredictionWeight.order(created_at: :desc).second
      if previous
        puts "Comparison with previous model:"
        puts "  Accuracy change: #{(model.accuracy - previous.accuracy).round(1)}%"
        puts "  Games increase: #{model.games_trained_on - previous.games_trained_on}"
        puts "=" * 60
      end
    else
      puts "ERROR: No training data available"
      puts "Make sure you have matches in the database"
    end
  end

  desc "Backfill heal stats (self_heal, team_heal, total_heal) from replay data"
  task backfill_heal_stats: :environment do
    puts "=" * 60
    puts "Backfilling Heal Stats"
    puts "=" * 60
    puts

    appearances_with_replay = Appearance.joins(match: :wc3stats_replay)
      .includes({ match: :wc3stats_replay }, :player, :faction)
    total = appearances_with_replay.count
    updated = 0
    skipped = 0

    puts "Appearances with replays: #{total}"
    puts

    appearances_with_replay.find_each.with_index do |appearance, index|
      replay = appearance.match.wc3stats_replay
      player = appearance.player

      # Find the player's data in the replay
      player_data = replay.players.find do |p|
        battletag = p["name"]
        fixed_battletag = replay.fix_encoding(battletag&.gsub("\\", "") || "")
        player.battletag == fixed_battletag || player.battletag == battletag
      end

      if player_data
        self_heal = player_data.dig("variables", "selfHeal")
        team_heal = player_data.dig("variables", "teamHeal")
        total_heal = (self_heal || 0) + (team_heal || 0) if self_heal || team_heal

        changes = {}
        changes[:self_heal] = self_heal if self_heal && appearance.self_heal != self_heal
        changes[:team_heal] = team_heal if team_heal && appearance.team_heal != team_heal
        changes[:total_heal] = total_heal if total_heal && appearance.total_heal != total_heal

        if changes.any?
          appearance.update_columns(changes)
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

  desc "Backfill castles_razed from replay data"
  task backfill_castles_razed: :environment do
    puts "=" * 60
    puts "Backfilling Castles Razed"
    puts "=" * 60
    puts

    appearances_with_replay = Appearance.joins(match: :wc3stats_replay)
      .includes({ match: :wc3stats_replay }, :player, :faction)
    total = appearances_with_replay.count
    updated = 0
    skipped = 0

    puts "Appearances with replays: #{total}"
    puts

    appearances_with_replay.find_each.with_index do |appearance, index|
      replay = appearance.match.wc3stats_replay
      player = appearance.player

      # Find the player's data in the replay
      player_data = replay.players.find do |p|
        battletag = p["name"]
        fixed_battletag = replay.fix_encoding(battletag&.gsub("\\", "") || "")
        player.battletag == fixed_battletag || player.battletag == battletag
      end

      if player_data
        castles_razed = player_data.dig("variables", "castlesRazed")
        if castles_razed && appearance.castles_razed != castles_razed
          appearance.update_column(:castles_razed, castles_razed)
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
