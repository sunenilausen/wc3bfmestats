module MatchesHelper
  def sort_link_for(column, label)
    current_sort = params[:sort] == column
    current_direction = params[:direction] || "desc"
    new_direction = current_sort && current_direction == "desc" ? "asc" : "desc"

    arrow = if current_sort
      current_direction == "asc" ? "▲" : "▼"
    else
      ""
    end

    link_to "#{label} #{arrow}".strip, matches_path(sort: column, direction: new_direction),
            class: "text-sm font-medium #{current_sort ? 'text-blue-600' : 'text-gray-600'} hover:text-blue-600"
  end

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

  def per_minute_unit_kills(appearances)
    total_seconds = appearances.first.match.seconds.to_f
    return 0 if total_seconds.zero?

    (sum_unit_kills(appearances) * 60 / total_seconds).round(2)
  end

  def per_minute_hero_kills(appearances)
    total_seconds = appearances.first.match.seconds.to_f
    return 0 if total_seconds.zero?

    (sum_hero_kills(appearances) * 60 / total_seconds).round(2)
  end
end
