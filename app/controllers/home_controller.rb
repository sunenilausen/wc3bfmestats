class HomeController < ApplicationController
  def index
    @underdog_stats = calculate_underdog_stats
    @matches_count = Match.count
    @players_count = Player.joins(:matches).distinct.count
    @observers_count = Player.left_joins(:matches).where(matches: { id: nil }).count
  end

  private

  def calculate_underdog_stats
    matches_with_data = Match.includes(appearances: :faction).where.not(good_victory: nil)

    underdog_wins = 0
    total_matches = 0

    matches_with_data.find_each do |match|
      good_appearances = match.appearances.select { |a| a.faction&.good? }
      evil_appearances = match.appearances.select { |a| a.faction && !a.faction.good? }

      good_elos = good_appearances.map(&:elo_rating).compact
      evil_elos = evil_appearances.map(&:elo_rating).compact

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
end
