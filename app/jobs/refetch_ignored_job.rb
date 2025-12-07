class RefetchIgnoredJob < ApplicationJob
  queue_as :default

  # Refetches recent auto-ignored matches that might have been fixed on wc3stats
  # @param limit [Integer] number of ignored matches to check
  def perform(limit = 20)
    Rails.logger.info "RefetchIgnoredJob: Starting refetch of last #{limit} auto-ignored matches"

    refetchable = find_refetchable_matches(limit)

    if refetchable.empty?
      Rails.logger.info "RefetchIgnoredJob: No refetchable auto-ignored matches found"
      return
    end

    Rails.logger.info "RefetchIgnoredJob: Found #{refetchable.size} matches to refetch"

    refetched = 0
    now_valid = 0
    failed = 0

    refetchable.each do |item|
      replay_id = item[:replay].wc3stats_replay_id

      # Delete match and replay
      item[:match].destroy
      item[:replay].destroy

      # Refetch from wc3stats
      replay_fetcher = Wc3stats::ReplayFetcher.new(replay_id)
      new_replay = replay_fetcher.call

      if new_replay
        # Build match from replay
        builder = Wc3stats::MatchBuilder.new(new_replay)
        if builder.call
          refetched += 1
          now_valid += 1 unless new_replay.match&.ignored?
        else
          failed += 1
          Rails.logger.warn "RefetchIgnoredJob: Failed to build match for replay #{replay_id}"
        end
      else
        failed += 1
        Rails.logger.warn "RefetchIgnoredJob: Failed to fetch replay #{replay_id}: #{replay_fetcher.errors.first}"
      end

      # Be respectful to the API
      sleep 0.5
    end

    Rails.logger.info "RefetchIgnoredJob: Completed - refetched: #{refetched}, now valid: #{now_valid}, failed: #{failed}"

    # Recalculate ratings if any matches became valid
    if now_valid > 0
      Rails.logger.info "RefetchIgnoredJob: Recalculating ratings for #{now_valid} newly valid matches"
      CustomRatingRecalculator.new.call
      MlScoreRecalculator.new.call
    end
  end

  private

  def find_refetchable_matches(limit)
    # Find recent ignored matches with replays, ordered by most recent first
    ignored_matches = Match.where(ignored: true)
      .joins(:wc3stats_replay)
      .includes(:wc3stats_replay)
      .order(uploaded_at: :desc)
      .limit(limit * 3) # Fetch more to account for filtering

    refetchable = []

    ignored_matches.each do |match|
      replay = match.wc3stats_replay
      next unless replay

      # Skip test maps - they won't change
      next if replay.test_map?

      # Skip if fewer than 10 players in slots - won't change
      players_in_slots = replay.players.count { |p| p["slot"].present? && p["slot"] >= 0 && p["slot"] <= 9 }
      next if players_in_slots < 10

      # Include: no winner label or too short (these might be fixed on wc3stats)
      has_no_winner = replay.incomplete_game? && players_in_slots == 10
      too_short = replay.game_length.present? && replay.game_length < 120

      if has_no_winner || too_short
        refetchable << { match: match, replay: replay }
      end

      break if refetchable.size >= limit
    end

    refetchable
  end
end
