class Wc3statsSyncJob < ApplicationJob
  queue_as :default

  # Performs a sync of WC3Stats replays
  # @param mode [String] "recent" for last N matches, "full" for all matches
  # @param limit [Integer] number of replays to fetch (only used in "recent" mode)
  def perform(mode = "recent", limit = 5)
    case mode
    when "recent"
      sync_recent(limit)
    when "full"
      sync_full
    else
      Rails.logger.error "Wc3statsSyncJob: Unknown mode '#{mode}'"
    end
  end

  private

  def sync_recent(limit = 5)
    Rails.logger.info "Wc3statsSyncJob: Starting recent sync (last #{limit} replays)"

    # Fetch recent replay IDs
    fetcher = Wc3stats::GamesFetcher.new(search_term: "BFME", limit: limit)
    replay_ids = fetcher.call

    if fetcher.errors.any?
      Rails.logger.error "Wc3statsSyncJob: Errors fetching replay IDs: #{fetcher.errors.join(', ')}"
    end

    import_replays(replay_ids)
    post_import_tasks
  end

  def sync_full
    Rails.logger.info "Wc3statsSyncJob: Starting full sync (all replays)"

    # Fetch all replay IDs
    fetcher = Wc3stats::GamesFetcher.new(search_term: "BFME")
    replay_ids = fetcher.call

    if fetcher.errors.any?
      Rails.logger.error "Wc3statsSyncJob: Errors fetching replay IDs: #{fetcher.errors.join(', ')}"
    end

    import_replays(replay_ids)
    post_import_tasks
  end

  def import_replays(replay_ids)
    return if replay_ids.empty?

    # Filter out already imported replays
    existing_ids = Wc3statsReplay.where(wc3stats_replay_id: replay_ids).pluck(:wc3stats_replay_id)
    new_replay_ids = replay_ids - existing_ids

    Rails.logger.info "Wc3statsSyncJob: Found #{replay_ids.count} replays, #{new_replay_ids.count} new"

    imported = 0
    failed = 0

    new_replay_ids.each do |replay_id|
      replay_fetcher = Wc3stats::ReplayFetcher.new(replay_id)
      if replay_fetcher.call
        imported += 1
      else
        failed += 1
        Rails.logger.warn "Wc3statsSyncJob: Failed to import replay #{replay_id}: #{replay_fetcher.errors.first}"
      end

      # Be respectful to the API
      sleep 0.5
    end

    Rails.logger.info "Wc3statsSyncJob: Imported #{imported} replays, #{failed} failed"
  end

  def post_import_tasks
    # Build matches from replays
    build_matches

    # Mark invalid matches as ignored
    mark_invalid_matches

    # Set ignore flags on kill stats
    set_ignore_kill_flags

    # Backfill ordering fields
    backfill_ordering_fields

    # Create observer players
    create_observers

    # Fix unicode encoding
    fix_unicode_names

    # Backfill APM data
    backfill_apm

    # Refetch last auto-ignored match (in case it was fixed on wc3stats)
    refetch_last_ignored

    # Recalculate ratings and retrain model if needed
    recalculate_ratings

    # Calculate stay/leave percentages
    recalculate_stay_leave
  end

  def set_ignore_kill_flags
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
      Rails.logger.info "Wc3statsSyncJob: Set ignore flags on #{updated_unit} unit kills, #{updated_hero} hero kills"
    end
  end

  def backfill_ordering_fields
    matches_needing_backfill = Match.joins(:wc3stats_replay)
                                    .where("major_version IS NULL OR uploaded_at IS NULL")
                                    .includes(:wc3stats_replay)
    backfill_count = 0

    matches_needing_backfill.find_each do |match|
      replay = match.wc3stats_replay
      changes = {}

      changes[:major_version] = replay.major_version if match.major_version.nil? && replay.major_version
      changes[:build_version] = replay.build_version if match.build_version.nil? && replay.build_version
      changes[:map_version] = replay.map_version if match.map_version.nil? && replay.map_version
      changes[:uploaded_at] = replay.played_at if match.uploaded_at.nil? && replay.played_at

      if changes.any?
        match.update_columns(changes)
        backfill_count += 1
      end
    end

    if backfill_count > 0
      Rails.logger.info "Wc3statsSyncJob: Backfilled ordering fields for #{backfill_count} matches"
    end
  end

  def create_observers
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

        # Create player if not exists (check alternative_battletags for merged players)
        unless Player.exists_by_any_battletag?(fixed_battletag) || Player.exists_by_any_battletag?(battletag)
          nickname = fixed_battletag.split("#").first
          Player.create!(
            battletag: fixed_battletag,
            nickname: nickname,
            custom_rating: NewPlayerDefaults::CUSTOM_RATING,
            ml_score: NewPlayerDefaults::ML_SCORE
          )
          observers_created += 1
        end
      end
    end

    if observers_created > 0
      Rails.logger.info "Wc3statsSyncJob: Created #{observers_created} new observer players"
    end
  end

  def mark_invalid_matches
    # Mark matches with != 10 appearances as ignored
    invalid_matches = Match.left_joins(:appearances)
                           .where(ignored: false)
                           .group(:id)
                           .having("COUNT(appearances.id) != 10")
    invalid_count = 0
    invalid_matches.find_each do |match|
      match.update_column(:ignored, true)
      invalid_count += 1
    end

    # Mark test maps as ignored
    test_map_count = 0
    Match.joins(:wc3stats_replay).where(ignored: false).find_each do |match|
      if match.wc3stats_replay&.test_map?
        match.update_column(:ignored, true)
        test_map_count += 1
      end
    end

    total = invalid_count + test_map_count
    if total > 0
      Rails.logger.info "Wc3statsSyncJob: Marked #{total} invalid matches as ignored (#{invalid_count} incomplete, #{test_map_count} test maps)"
    end
  end

  def build_matches
    replays_without_matches = Wc3statsReplay.left_joins(:match).where(matches: { id: nil })
    count = replays_without_matches.count

    return if count.zero?

    Rails.logger.info "Wc3statsSyncJob: Building matches for #{count} replays"

    created = 0
    replays_without_matches.find_each do |replay|
      builder = Wc3stats::MatchBuilder.new(replay)
      created += 1 if builder.call
    end

    Rails.logger.info "Wc3statsSyncJob: Created #{created} matches"
  end

  def fix_unicode_names
    fixer = UnicodeNameFixer.new
    fixer.call

    if fixer.fixed_count > 0
      Rails.logger.info "Wc3statsSyncJob: Fixed #{fixer.fixed_count} player names with encoding issues"
    end
  end

  def refetch_last_ignored
    # Find the most recent auto-ignored match that might be fixable
    ignored_match = Match.where(ignored: true)
      .joins(:wc3stats_replay)
      .includes(:wc3stats_replay)
      .order(uploaded_at: :desc)
      .limit(10)
      .find do |match|
        replay = match.wc3stats_replay
        next false unless replay
        next false if replay.test_map?

        players_in_slots = replay.players.count { |p| p["slot"].present? && p["slot"] >= 0 && p["slot"] <= 9 }
        next false if players_in_slots < 10

        # Only refetch if no winner or too short
        has_no_winner = replay.incomplete_game? && players_in_slots == 10
        too_short = replay.game_length.present? && replay.game_length < 120
        has_no_winner || too_short
      end

    return unless ignored_match

    replay = ignored_match.wc3stats_replay
    replay_id = replay.wc3stats_replay_id

    Rails.logger.info "Wc3statsSyncJob: Refetching last auto-ignored match (replay #{replay_id})"

    # Delete and refetch
    ignored_match.destroy
    replay.destroy

    replay_fetcher = Wc3stats::ReplayFetcher.new(replay_id)
    new_replay = replay_fetcher.call

    if new_replay
      builder = Wc3stats::MatchBuilder.new(new_replay)
      if builder.call
        status = new_replay.match&.ignored? ? "still ignored" : "now valid"
        Rails.logger.info "Wc3statsSyncJob: Refetched replay #{replay_id} - #{status}"
      else
        Rails.logger.warn "Wc3statsSyncJob: Failed to build match for replay #{replay_id}"
      end
    else
      Rails.logger.warn "Wc3statsSyncJob: Failed to fetch replay #{replay_id}: #{replay_fetcher.errors.first}"
    end
  end

  def recalculate_ratings
    # Count unprocessed matches (those without custom_rating on appearances)
    unprocessed_matches = Match.where(ignored: false)
                               .joins(:appearances)
                               .where(appearances: { custom_rating: nil })
                               .distinct

    unprocessed_count = unprocessed_matches.count
    Rails.logger.info "Wc3statsSyncJob: Found #{unprocessed_count} unprocessed match(es)"

    if unprocessed_count == 1
      # Single new match - try incremental processing
      match = unprocessed_matches.first
      Rails.logger.info "Wc3statsSyncJob: Attempting incremental processing for match ##{match.id}"
      if CustomRatingRecalculator.process_match_if_latest(match)
        Rails.logger.info "Wc3statsSyncJob: Processed single match incrementally (match ##{match.id})"
      else
        # Fall back to full recalc
        Rails.logger.info "Wc3statsSyncJob: Incremental processing failed for match ##{match.id}, doing full recalculation"
        full_recalculate
      end
    elsif unprocessed_count > 0
      # Multiple new matches - full recalculation needed
      Rails.logger.info "Wc3statsSyncJob: #{unprocessed_count} unprocessed matches, doing full recalculation"
      full_recalculate
    else
      Rails.logger.info "Wc3statsSyncJob: No unprocessed matches, skipping rating recalculation"
    end

    Rails.logger.info "Wc3statsSyncJob: Recalculating ML scores"
    ml = MlScoreRecalculator.new
    ml.call
  end

  def full_recalculate
    Rails.logger.info "Wc3statsSyncJob: Recalculating Custom Rating (full)"
    custom = CustomRatingRecalculator.new
    custom.call
  end

  def recalculate_stay_leave
    Rails.logger.info "Wc3statsSyncJob: Recalculating stay/leave percentages"
    recalculator = StayLeaveRecalculator.new
    recalculator.call
    Rails.logger.info "Wc3statsSyncJob: Updated #{recalculator.players_updated} players with stay/leave stats"
    if recalculator.errors.any?
      Rails.logger.warn "Wc3statsSyncJob: Stay/leave errors: #{recalculator.errors.count}"
    end
  end

  def backfill_apm
    Rails.logger.info "Wc3statsSyncJob: Backfilling APM data"
    backfiller = ApmBackfiller.new
    backfiller.call
    if backfiller.updated_count > 0
      Rails.logger.info "Wc3statsSyncJob: Updated #{backfiller.updated_count} appearances with APM data"
    end
    if backfiller.errors.any?
      Rails.logger.warn "Wc3statsSyncJob: APM backfill errors: #{backfiller.errors.count}"
    end
  end
end
