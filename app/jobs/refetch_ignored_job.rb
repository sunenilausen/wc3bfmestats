class RefetchIgnoredJob < ApplicationJob
  queue_as :default

  # Refetches recent auto-ignored matches that might have been fixed on wc3stats,
  # as well as matches with missing/incomplete data (no team heal data, 0 unit kills on all players)
  # @param limit [Integer] number of matches to check
  def perform(limit = 20)
    Rails.logger.info "RefetchIgnoredJob: Starting refetch of last #{limit} problematic matches"

    refetchable = find_refetchable_matches(limit)

    if refetchable.empty?
      Rails.logger.info "RefetchIgnoredJob: No refetchable matches found"
      return
    end

    Rails.logger.info "RefetchIgnoredJob: Found #{refetchable.size} matches to refetch"

    refetched = 0
    now_valid = 0
    failed = 0

    refetchable.each do |item|
      replay_id = item[:replay].wc3stats_replay_id
      reason = item[:reason]

      Rails.logger.info "RefetchIgnoredJob: Refetching replay #{replay_id} (#{reason})"

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
    refetchable = []

    # First, find recent ignored matches with replays
    ignored_matches = Match.where(ignored: true)
      .joins(:wc3stats_replay)
      .includes(:wc3stats_replay, :appearances)
      .order(uploaded_at: :desc)
      .limit(limit * 3)

    ignored_matches.each do |match|
      break if refetchable.size >= limit

      replay = match.wc3stats_replay
      next unless replay
      next if replay.test_map?

      players_in_slots = replay.players.count { |p| p["slot"].present? && p["slot"] >= 0 && p["slot"] <= 9 }
      next if players_in_slots < 10

      has_no_winner = replay.incomplete_game? && players_in_slots == 10
      too_short = replay.game_length.present? && replay.game_length < 120

      if has_no_winner || too_short
        refetchable << { match: match, replay: replay, reason: "ignored" }
      end
    end

    # Second, find non-ignored matches with incomplete data
    incomplete_matches = Match.where(ignored: false)
      .joins(:wc3stats_replay)
      .includes(:wc3stats_replay, :appearances)
      .order(uploaded_at: :desc)
      .limit(limit * 5)

    incomplete_matches.each do |match|
      break if refetchable.size >= limit

      replay = match.wc3stats_replay
      next unless replay
      next if replay.test_map?

      # Check for missing team heal data (all appearances have nil team_heal)
      appearances = match.appearances
      all_nil_team_heal = appearances.all? { |a| a.team_heal.nil? }

      # Check for all zero unit kills (unlikely in a real game)
      all_zero_unit_kills = appearances.all? { |a| a.unit_kills.nil? || a.unit_kills == 0 }

      if all_nil_team_heal || all_zero_unit_kills
        reason = []
        reason << "no team_heal data" if all_nil_team_heal
        reason << "all zero unit_kills" if all_zero_unit_kills
        refetchable << { match: match, replay: replay, reason: reason.join(", ") }
      end
    end

    refetchable
  end
end
