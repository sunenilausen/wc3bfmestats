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

    # Fix unicode encoding
    fix_unicode_names

    # Recalculate ratings
    recalculate_ratings
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

  def recalculate_ratings
    Rails.logger.info "Wc3statsSyncJob: Recalculating ELO ratings"
    elo = EloRecalculator.new
    elo.call

    Rails.logger.info "Wc3statsSyncJob: Recalculating Glicko-2 ratings"
    glicko = Glicko2Recalculator.new
    glicko.call
  end
end
