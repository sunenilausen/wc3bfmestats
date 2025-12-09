class HomeController < ApplicationController
  def index
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
    @map_version = if params.key?(:map_version)
      params[:map_version].presence  # nil if "All versions" selected
    else
      @available_map_versions.first  # default to newest on first visit
    end

    @underdog_stats = calculate_underdog_stats(@map_version)
    @ml_prediction_stats = calculate_ml_prediction_stats(@map_version)
    @recent_prediction_stats = calculate_recent_prediction_stats
    @recent_cr_stats = calculate_recent_cr_stats
    @good_vs_evil_stats = calculate_good_vs_evil_stats(@map_version)
    @avg_match_time = calculate_avg_match_time(@map_version)
    @matches_count = Match.where(ignored: false).count
    # Players who have played at least one valid (non-ignored) match
    @players_count = Player.joins(:matches).where(matches: { ignored: false }).distinct.count
    # Players who have never played a valid match (only observed or only played ignored matches)
    players_with_valid_matches = Player.joins(:matches).where(matches: { ignored: false }).distinct.pluck(:id)
    @observers_count = Player.where.not(id: players_with_valid_matches).count

    # Most recent lobby and match
    @recent_lobby = Lobby.order(updated_at: :desc).first
    @recent_match = Match.where(ignored: false).order(uploaded_at: :desc).includes(appearances: [ :player, :faction ]).first

    # User's most recent lobby (based on session)
    if session[:lobby_token].present?
      @my_lobby = Lobby.where(session_token: session[:lobby_token]).order(updated_at: :desc).first
    end
  end

  private

  def calculate_underdog_stats(map_version = nil)
    matches_with_data = Match.includes(appearances: :faction).where(ignored: false).where.not(good_victory: nil)
    matches_with_data = matches_with_data.where(map_version: map_version) if map_version.present?

    underdog_wins = 0
    total_matches = 0

    matches_with_data.find_each do |match|
      good_appearances = match.appearances.select { |a| a.faction&.good? }
      evil_appearances = match.appearances.select { |a| a.faction && !a.faction.good? }

      good_elos = good_appearances.map(&:custom_rating).compact
      evil_elos = evil_appearances.map(&:custom_rating).compact

      next if good_elos.empty? || evil_elos.empty?

      good_avg = good_elos.sum.to_f / good_elos.size
      evil_avg = evil_elos.sum.to_f / evil_elos.size

      next if good_avg == evil_avg

      total_matches += 1

      good_is_underdog = good_avg < evil_avg
      underdog_won = (good_is_underdog && match.good_victory) || (!good_is_underdog && !match.good_victory)

      underdog_wins += 1 if underdog_won
    end

    {
      underdog_wins: underdog_wins,
      total_matches: total_matches,
      percentage: total_matches > 0 ? (underdog_wins.to_f / total_matches * 100).round(1) : 0
    }
  end

  def calculate_good_vs_evil_stats(map_version = nil)
    matches_with_result = Match.where(ignored: false).where.not(good_victory: nil)
    matches_with_result = matches_with_result.where(map_version: map_version) if map_version.present?

    total = matches_with_result.count
    good_wins = matches_with_result.where(good_victory: true).count
    evil_wins = total - good_wins

    {
      good_wins: good_wins,
      evil_wins: evil_wins,
      total: total,
      good_percentage: total > 0 ? (good_wins.to_f / total * 100).round(1) : 0,
      evil_percentage: total > 0 ? (evil_wins.to_f / total * 100).round(1) : 0
    }
  end

  def calculate_avg_match_time(map_version = nil)
    matches = Match.where(ignored: false).where.not(seconds: nil)
    matches = matches.where(map_version: map_version) if map_version.present?

    count = matches.count
    return { avg_seconds: 0, avg_formatted: "-", count: 0 } if count.zero?

    avg_seconds = matches.average(:seconds).to_f.round
    minutes = avg_seconds / 60
    formatted = "#{minutes.round}m"

    {
      avg_seconds: avg_seconds,
      avg_formatted: formatted,
      count: count
    }
  end

  def calculate_ml_prediction_stats(map_version = nil)
    matches = Match.where(ignored: false)
                   .where.not(good_victory: nil)
                   .where.not(predicted_good_win_pct: nil)
    matches = matches.where(map_version: map_version) if map_version.present?

    correct_predictions = 0
    underdog_wins = 0
    total_matches = 0
    underdog_matches = 0

    matches.find_each do |match|
      total_matches += 1

      good_pct = match.predicted_good_win_pct.to_f
      good_favored = good_pct >= 50
      prediction_correct = (good_favored && match.good_victory) || (!good_favored && !match.good_victory)

      correct_predictions += 1 if prediction_correct

      # Track underdog wins (team with < 50% predicted win chance)
      next if good_pct == 50  # Skip even matchups

      underdog_matches += 1
      underdog_won = (good_pct < 50 && match.good_victory) || (good_pct > 50 && !match.good_victory)
      underdog_wins += 1 if underdog_won
    end

    {
      correct_predictions: correct_predictions,
      total_matches: total_matches,
      accuracy: total_matches > 0 ? (correct_predictions.to_f / total_matches * 100).round(1) : 0,
      underdog_wins: underdog_wins,
      underdog_matches: underdog_matches,
      underdog_win_rate: underdog_matches > 0 ? (underdog_wins.to_f / underdog_matches * 100).round(1) : 0
    }
  end

  def calculate_recent_prediction_stats
    # Get last 100 matches in chronological order (most recent)
    matches = Match.where(ignored: false)
                   .where.not(good_victory: nil)
                   .where.not(predicted_good_win_pct: nil)
                   .reverse_chronological
                   .limit(100)

    correct_predictions = 0
    underdog_wins = 0
    total_matches = 0
    underdog_matches = 0

    matches.each do |match|
      total_matches += 1

      good_pct = match.predicted_good_win_pct.to_f
      good_favored = good_pct >= 50
      prediction_correct = (good_favored && match.good_victory) || (!good_favored && !match.good_victory)

      correct_predictions += 1 if prediction_correct

      # Track underdog wins (team with < 50% predicted win chance)
      next if good_pct == 50  # Skip even matchups

      underdog_matches += 1
      underdog_won = (good_pct < 50 && match.good_victory) || (good_pct > 50 && !match.good_victory)
      underdog_wins += 1 if underdog_won
    end

    {
      correct_predictions: correct_predictions,
      total_matches: total_matches,
      accuracy: total_matches > 0 ? (correct_predictions.to_f / total_matches * 100).round(1) : 0,
      underdog_wins: underdog_wins,
      underdog_matches: underdog_matches,
      underdog_win_rate: underdog_matches > 0 ? (underdog_wins.to_f / underdog_matches * 100).round(1) : 0
    }
  end

  def calculate_recent_cr_stats
    # Get last 100 matches based on CR (custom rating) prediction
    matches = Match.includes(appearances: :faction)
                   .where(ignored: false)
                   .where.not(good_victory: nil)
                   .reverse_chronological
                   .limit(100)

    underdog_wins = 0
    total_matches = 0

    matches.each do |match|
      good_appearances = match.appearances.select { |a| a.faction&.good? }
      evil_appearances = match.appearances.select { |a| a.faction && !a.faction.good? }

      good_crs = good_appearances.map(&:custom_rating).compact
      evil_crs = evil_appearances.map(&:custom_rating).compact

      next if good_crs.empty? || evil_crs.empty?

      good_avg = good_crs.sum.to_f / good_crs.size
      evil_avg = evil_crs.sum.to_f / evil_crs.size

      next if good_avg == evil_avg

      total_matches += 1

      good_is_underdog = good_avg < evil_avg
      underdog_won = (good_is_underdog && match.good_victory) || (!good_is_underdog && !match.good_victory)

      underdog_wins += 1 if underdog_won
    end

    {
      underdog_wins: underdog_wins,
      total_matches: total_matches,
      underdog_win_rate: total_matches > 0 ? (underdog_wins.to_f / total_matches * 100).round(1) : 0
    }
  end
end
