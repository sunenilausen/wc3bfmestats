class HomeController < ApplicationController
  def index
    @available_map_versions = Rails.cache.fetch(["available_map_versions", StatsCacheKey.key]) do
      Match.where(ignored: false)
        .where.not(map_version: nil)
        .distinct
        .pluck(:map_version)
        .sort_by do |v|
          match = v.match(/^(\d+)\.(\d+)([a-zA-Z]*)/)
          if match
            [match[1].to_i, match[2].to_i, match[3].to_s]
          else
            [0, 0, v]
          end
        end
        .reverse
    end

    # Default to newest map version if not specified
    @map_version = params[:map_version].presence || @available_map_versions.first

    @underdog_stats = calculate_underdog_stats
    @good_vs_evil_stats = calculate_good_vs_evil_stats(@map_version)
    @matches_count = Match.where(ignored: false).count
    # Players who have played at least one valid (non-ignored) match
    @players_count = Player.joins(:matches).where(matches: { ignored: false }).distinct.count
    # Players who have never played a valid match (only observed or only played ignored matches)
    players_with_valid_matches = Player.joins(:matches).where(matches: { ignored: false }).distinct.pluck(:id)
    @observers_count = Player.where.not(id: players_with_valid_matches).count

    # Most recent lobby and match
    @recent_lobby = Lobby.order(updated_at: :desc).first
    @recent_match = Match.where(ignored: false).order(uploaded_at: :desc).includes(appearances: [:player, :faction]).first

    # User's most recent lobby (based on session)
    if session[:lobby_token].present?
      @my_lobby = Lobby.where(session_token: session[:lobby_token]).order(updated_at: :desc).first
    end
  end

  private

  def calculate_underdog_stats
    matches_with_data = Match.includes(appearances: :faction).where(ignored: false).where.not(good_victory: nil)

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
end
