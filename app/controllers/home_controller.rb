class HomeController < ApplicationController
  def index
    # Cache all home page counts together
    home_counts = Rails.cache.fetch([ "home_counts", StatsCacheKey.key ]) do
      compute_home_counts
    end

    @matches_count = home_counts[:matches_count]
    @players_count = home_counts[:players_count]
    @observers_count = home_counts[:observers_count]

    # Cache recent lobbies separately (changes more frequently)
    @recent_lobbies = Rails.cache.fetch([ "home_recent_lobbies", Lobby.maximum(:updated_at) ], expires_in: 1.minute) do
      Lobby.order(updated_at: :desc).limit(2).includes(lobby_players: [ :faction, :player ]).to_a
    end

    # Cache recent matches (changes less frequently)
    @recent_matches = Rails.cache.fetch([ "home_recent_matches", StatsCacheKey.key ]) do
      Match.where(ignored: false)
        .order(uploaded_at: :desc)
        .includes(appearances: [ :player, :faction ])
        .limit(3)
        .to_a
    end

    # User's most recent lobby (based on session) - not cached, user-specific
    if session[:lobby_token].present?
      @my_lobby = Lobby.where(session_token: session[:lobby_token])
        .order(updated_at: :desc)
        .includes(lobby_players: [ :faction, :player ])
        .first
    end
  end

  def statistics
    @available_map_versions = Rails.cache.fetch([ "available_map_versions", StatsCacheKey.key ]) do
      Match.where(ignored: false)
        .where.not(map_version: nil)
        .distinct
        .pluck(:map_version)
        .sort_by do |v|
          match = v.match(/^(\d+)\.(\d+)([a-zA-Z]*)/)
          if match
            [ match[1].to_i, match[2].to_i, match[3].to_s ]
          else
            [ 0, 0, v ]
          end
        end
        .reverse
    end

    # Default to newest map version if not specified
    # If map_version param exists (even if empty), use it; otherwise default to newest
    @version_filter = if params.key?(:map_version)
      params[:map_version].presence  # nil if "All versions" selected
    else
      @available_map_versions.first  # default to newest on first visit
    end

    # Parse filter (can be "last:100", "from:4.5e", or single version like "4.6")
    @map_version = nil
    @map_versions = nil
    @last_n_games = nil
    if @version_filter.present?
      if @version_filter.start_with?("last:")
        @last_n_games = @version_filter.sub("last:", "").to_i
      elsif @version_filter.start_with?("from:")
        from_version = @version_filter.sub("from:", "")
        until_index = @available_map_versions.index(from_version)
        @map_versions = until_index ? @available_map_versions[0..until_index] : @available_map_versions
      else
        @map_version = @version_filter
      end
    end

    @underdog_stats = calculate_underdog_stats(@map_version, @last_n_games, @map_versions)
    @ml_prediction_stats = calculate_ml_prediction_stats(@map_version, @last_n_games, @map_versions)
    @good_vs_evil_stats = calculate_good_vs_evil_stats(@map_version, @last_n_games, @map_versions)
    @balanced_games_stats = calculate_balanced_games_stats(@map_version, @last_n_games, @map_versions)
    @prediction_accuracy_by_confidence = calculate_prediction_accuracy_by_confidence(@map_version, @last_n_games, @map_versions)
    @avg_match_time = calculate_avg_match_time(@map_version, @last_n_games, @map_versions)
    @matches_count = Match.where(ignored: false).count
    # Players who have played at least one valid (non-ignored) match
    @players_count = Player.joins(:matches).where(matches: { ignored: false }).distinct.count
    # Players who have never played a valid match (only observed or only played ignored matches)
    players_with_valid_matches = Player.joins(:matches).where(matches: { ignored: false }).distinct.pluck(:id)
    @observers_count = Player.where.not(id: players_with_valid_matches).count
  end

  private

  def compute_home_counts
    matches_count = Match.where(ignored: false).count

    # Use a single query to get player IDs with valid matches
    players_with_matches = Player.joins(:matches)
      .where(matches: { ignored: false })
      .distinct

    players_count = players_with_matches.count
    observers_count = Player.count - players_count

    {
      matches_count: matches_count,
      players_count: players_count,
      observers_count: observers_count
    }
  end

  def calculate_underdog_stats(map_version = nil, limit = nil, map_versions = nil)
    matches_with_data = Match.includes(appearances: :faction).where(ignored: false).where.not(good_victory: nil)
    matches_with_data = matches_with_data.where(map_version: map_version) if map_version.present?
    matches_with_data = matches_with_data.where(map_version: map_versions) if map_versions.present?
    matches_with_data = matches_with_data.reverse_chronological.limit(limit) if limit.present? && limit > 0

    underdog_wins = 0
    favorite_wins = 0
    underdog_matches = 0
    favorite_matches = 0

    matches_with_data.find_each do |match|
      good_appearances = match.appearances.select { |a| a.faction&.good? }
      evil_appearances = match.appearances.select { |a| a.faction && !a.faction.good? }

      good_crs = good_appearances.map(&:custom_rating).compact
      evil_crs = evil_appearances.map(&:custom_rating).compact

      next if good_crs.empty? || evil_crs.empty?

      good_avg = good_crs.sum.to_f / good_crs.size
      evil_avg = evil_crs.sum.to_f / evil_crs.size

      # Convert CR difference to win probability (same formula as LobbyWinPredictor)
      cr_diff = good_avg - evil_avg
      good_pct = (1.0 / (1 + Math.exp(-cr_diff / 150.0)) * 100)

      # Track underdog wins (<40% predicted win chance)
      if good_pct < 45 || good_pct > 55
        if good_pct < 45
          underdog_matches += 1
          underdog_wins += 1 if match.good_victory
          favorite_matches += 1
          favorite_wins += 1 unless match.good_victory
        else # good_pct > 60
          favorite_matches += 1
          favorite_wins += 1 if match.good_victory
          underdog_matches += 1
          underdog_wins += 1 unless match.good_victory
        end
      end
    end

    {
      underdog_wins: underdog_wins,
      underdog_matches: underdog_matches,
      percentage: underdog_matches > 0 ? (underdog_wins.to_f / underdog_matches * 100).round(1) : 0,
      favorite_wins: favorite_wins,
      favorite_matches: favorite_matches,
      favorite_percentage: favorite_matches > 0 ? (favorite_wins.to_f / favorite_matches * 100).round(1) : 0
    }
  end

  def calculate_good_vs_evil_stats(map_version = nil, limit = nil, map_versions = nil)
    matches_with_result = Match.where(ignored: false).where.not(good_victory: nil)
    matches_with_result = matches_with_result.where(map_version: map_version) if map_version.present?
    matches_with_result = matches_with_result.where(map_version: map_versions) if map_versions.present?
    matches_with_result = matches_with_result.reverse_chronological.limit(limit) if limit.present? && limit > 0

    # When using limit, we need to load records first since .count after .where doesn't respect limit
    if limit.present? && limit > 0
      loaded = matches_with_result.to_a
      total = loaded.size
      good_wins = loaded.count { |m| m.good_victory }
    else
      total = matches_with_result.count
      good_wins = matches_with_result.where(good_victory: true).count
    end
    evil_wins = total - good_wins

    {
      good_wins: good_wins,
      evil_wins: evil_wins,
      total: total,
      good_percentage: total > 0 ? (good_wins.to_f / total * 100).round(1) : 0,
      evil_percentage: total > 0 ? (evil_wins.to_f / total * 100).round(1) : 0
    }
  end

  def calculate_avg_match_time(map_version = nil, limit = nil, map_versions = nil)
    matches = Match.where(ignored: false).where.not(seconds: nil)
    matches = matches.where(map_version: map_version) if map_version.present?
    matches = matches.where(map_version: map_versions) if map_versions.present?
    matches = matches.reverse_chronological.limit(limit) if limit.present? && limit > 0

    # When using limit, load records first since .average doesn't respect limit
    if limit.present? && limit > 0
      loaded = matches.pluck(:seconds)
      count = loaded.size
      return { avg_seconds: 0, avg_formatted: "-", count: 0 } if count.zero?
      avg_seconds = (loaded.sum.to_f / count).round
    else
      count = matches.count
      return { avg_seconds: 0, avg_formatted: "-", count: 0 } if count.zero?
      avg_seconds = matches.average(:seconds).to_f.round
    end

    minutes = avg_seconds / 60
    formatted = "#{minutes.round}m"

    {
      avg_seconds: avg_seconds,
      avg_formatted: formatted,
      count: count
    }
  end

  def calculate_ml_prediction_stats(map_version = nil, limit = nil, map_versions = nil)
    matches = Match.where(ignored: false)
                   .where.not(good_victory: nil)
                   .where.not(predicted_good_win_pct: nil)
    matches = matches.where(map_version: map_version) if map_version.present?
    matches = matches.where(map_version: map_versions) if map_versions.present?
    matches = matches.reverse_chronological.limit(limit) if limit.present? && limit > 0

    correct_predictions = 0
    underdog_wins = 0
    favorite_wins = 0
    total_matches = 0
    underdog_matches = 0
    favorite_matches = 0

    matches.find_each do |match|
      total_matches += 1

      good_pct = match.predicted_good_win_pct.to_f
      good_favored = good_pct >= 50
      prediction_correct = (good_favored && match.good_victory) || (!good_favored && !match.good_victory)

      correct_predictions += 1 if prediction_correct

      # Track underdog wins (<40% predicted win chance)
      if good_pct < 45 || good_pct > 55
        if good_pct < 45
          underdog_matches += 1
          underdog_wins += 1 if match.good_victory
          favorite_matches += 1
          favorite_wins += 1 unless match.good_victory
        else # good_pct > 60
          favorite_matches += 1
          favorite_wins += 1 if match.good_victory
          underdog_matches += 1
          underdog_wins += 1 unless match.good_victory
        end
      end
    end

    {
      correct_predictions: correct_predictions,
      total_matches: total_matches,
      accuracy: total_matches > 0 ? (correct_predictions.to_f / total_matches * 100).round(1) : 0,
      underdog_wins: underdog_wins,
      underdog_matches: underdog_matches,
      underdog_win_rate: underdog_matches > 0 ? (underdog_wins.to_f / underdog_matches * 100).round(1) : 0,
      favorite_wins: favorite_wins,
      favorite_matches: favorite_matches,
      favorite_win_rate: favorite_matches > 0 ? (favorite_wins.to_f / favorite_matches * 100).round(1) : 0
    }
  end

  def calculate_prediction_accuracy_by_confidence(map_version = nil, limit = nil, map_versions = nil)
    matches = Match.includes(appearances: :faction)
                   .where(ignored: false)
                   .where.not(good_victory: nil)
                   .where.not(predicted_good_win_pct: nil)
    matches = matches.where(map_version: map_version) if map_version.present?
    matches = matches.where(map_version: map_versions) if map_versions.present?
    matches = matches.reverse_chronological.limit(limit) if limit.present? && limit > 0

    # Buckets in 5% increments from 50% to 100%
    buckets = {}
    (50..95).step(5).each do |start|
      label = "#{start}-#{start + 5}"
      buckets[label] = { correct: 0, total: 0, cr_correct: 0, cr_total: 0 }
    end

    matches.find_each do |match|
      # CR+ prediction
      good_pct = match.predicted_good_win_pct.to_f
      confidence_pct = [ good_pct, 100 - good_pct ].max
      good_favored = good_pct >= 50
      prediction_correct = (good_favored && match.good_victory) || (!good_favored && !match.good_victory)

      bucket_key = bucket_for_confidence(confidence_pct)
      buckets[bucket_key][:total] += 1
      buckets[bucket_key][:correct] += 1 if prediction_correct

      # CR-only prediction (calculated from appearances)
      good_crs = match.appearances.select { |a| a.faction&.good? }.filter_map(&:custom_rating)
      evil_crs = match.appearances.reject { |a| a.faction&.good? }.filter_map(&:custom_rating)

      if good_crs.any? && evil_crs.any?
        good_cr_avg = good_crs.sum / good_crs.size.to_f
        evil_cr_avg = evil_crs.sum / evil_crs.size.to_f
        cr_diff = good_cr_avg - evil_cr_avg
        # Same formula as LobbyWinPredictor
        cr_good_pct = (1.0 / (1 + Math.exp(-cr_diff / 150.0)) * 100)

        cr_confidence_pct = [ cr_good_pct, 100 - cr_good_pct ].max
        cr_good_favored = cr_good_pct >= 50
        cr_prediction_correct = (cr_good_favored && match.good_victory) || (!cr_good_favored && !match.good_victory)

        cr_bucket_key = bucket_for_confidence(cr_confidence_pct)
        buckets[cr_bucket_key][:cr_total] += 1
        buckets[cr_bucket_key][:cr_correct] += 1 if cr_prediction_correct
      end
    end

    # Convert to array with percentages
    buckets.map do |label, data|
      {
        label: label,
        accuracy: data[:total] > 0 ? (data[:correct].to_f / data[:total] * 100).round(1) : nil,
        total: data[:total],
        cr_accuracy: data[:cr_total] > 0 ? (data[:cr_correct].to_f / data[:cr_total] * 100).round(1) : nil,
        cr_total: data[:cr_total]
      }
    end
  end

  def bucket_for_confidence(pct)
    bucket_start = ((pct.to_i / 5) * 5).clamp(50, 95)
    "#{bucket_start}-#{bucket_start + 5}"
  end

  # Calculate how many games are "balanced" (neither team heavily favored)
  # A balanced game is one where prediction is 45-55%
  def calculate_balanced_games_stats(map_version = nil, limit = nil, map_versions = nil)
    matches = Match.includes(appearances: :faction)
                   .where(ignored: false)
    matches = matches.where(map_version: map_version) if map_version.present?
    matches = matches.where(map_version: map_versions) if map_versions.present?
    matches = matches.reverse_chronological.limit(limit) if limit.present? && limit > 0

    total_matches = 0
    balanced_cr_ml = 0
    balanced_cr_only = 0

    matches.find_each do |match|
      # CR+ balanced (from stored prediction)
      if match.predicted_good_win_pct.present?
        total_matches += 1
        good_pct = match.predicted_good_win_pct.to_f
        balanced_cr_ml += 1 if good_pct >= 45 && good_pct <= 55
      end

      # CR-only balanced (calculate from appearances)
      good_crs = match.appearances.select { |a| a.faction&.good? }.filter_map(&:custom_rating)
      evil_crs = match.appearances.reject { |a| a.faction&.good? }.filter_map(&:custom_rating)

      if good_crs.any? && evil_crs.any?
        good_avg = good_crs.sum / good_crs.size.to_f
        evil_avg = evil_crs.sum / evil_crs.size.to_f
        cr_diff = good_avg - evil_avg

        # Convert CR difference to win probability (same formula as LobbyWinPredictor)
        cr_good_pct = (1.0 / (1 + Math.exp(-cr_diff / 150.0)) * 100)
        balanced_cr_only += 1 if cr_good_pct >= 45 && cr_good_pct <= 55
      end
    end

    {
      balanced_cr_ml: balanced_cr_ml,
      balanced_cr_only: balanced_cr_only,
      total_matches: total_matches,
      cr_ml_percentage: total_matches > 0 ? (balanced_cr_ml.to_f / total_matches * 100).round(1) : 0,
      cr_only_percentage: total_matches > 0 ? (balanced_cr_only.to_f / total_matches * 100).round(1) : 0
    }
  end
end
