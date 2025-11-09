module MatchesHelper
  def sum_unit_kills(appearances)
    appearances.to_a.sum { |appearance| appearance[:unit_kills].to_i }
  end

  def sum_hero_kills(appearances)
    appearances.to_a.sum { |appearance| appearance[:hero_kills].to_i }
  end

  def avg_unit_kills(appearances)
    (sum_unit_kills(appearances).to_f / appearances.size).round(2)
  end

  def avg_hero_kills(appearances)
    (sum_hero_kills(appearances).to_f / appearances.size).round(2)
  end

  def avg_elo_rating(appearances)
    total_elo = appearances.to_a.sum { |appearance| appearance.elo_rating.to_i }
    (total_elo.to_f / appearances.size).round
  end
end
