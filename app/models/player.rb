class Player < ApplicationRecord
  has_many :appearances
  has_many :matches, through: :appearances
  has_many :lobby_players
  has_many :lobbies, through: :lobby_players

  def wins
    appearances.joins(:match, :faction)
      .where(factions: { good: true }, matches: { good_victory: true })
      .or(appearances.joins(:match, :faction)
        .where(factions: { good: false }, matches: { good_victory: false }))
      .count
  end

  def losses
    matches.count - wins
  end

  def recent_wins(days: 100)
    cutoff = days.days.ago
    appearances.joins(:match, :faction)
      .where(matches: { played_at: cutoff.. })
      .where(factions: { good: true }, matches: { good_victory: true })
      .or(appearances.joins(:match, :faction)
        .where(matches: { played_at: cutoff.. })
        .where(factions: { good: false }, matches: { good_victory: false }))
      .count
  end

  def recent_losses(days: 100)
    cutoff = days.days.ago
    recent_matches = matches.where(played_at: cutoff..).count
    recent_matches - recent_wins(days: days)
  end

  def recent_wins_with_faction(faction, days: 100)
    cutoff = days.days.ago
    won = faction.good? ? true : false
    appearances.joins(:match)
      .where(faction: faction)
      .where(matches: { played_at: cutoff.., good_victory: won })
      .count
  end

  def recent_losses_with_faction(faction, days: 100)
    cutoff = days.days.ago
    recent_with_faction = appearances.joins(:match)
      .where(faction: faction)
      .where(matches: { played_at: cutoff.. })
      .count
    recent_with_faction - recent_wins_with_faction(faction, days: days)
  end

  def wins_with_faction(faction)
    won = faction.good? ? true : false
    appearances.joins(:match)
      .where(faction: faction)
      .where(matches: { good_victory: won })
      .count
  end

  def losses_with_faction(faction)
    total_with_faction = appearances.where(faction: faction).count
    total_with_faction - wins_with_faction(faction)
  end

  def win_rate_with_faction(faction)
    total = appearances.where(faction: faction).count
    return 0 if total.zero?
    (wins_with_faction(faction).to_f / total * 100).round(1)
  end

  def times_top_hero_kills_with_faction(faction)
    appearances.includes(:match).where(faction: faction).count do |appearance|
      next false unless appearance.hero_kills.present?

      match = appearance.match
      player_good = faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.hero_kills.present?
      end

      next false if team_appearances.empty?

      max_hero_kills = team_appearances.map(&:hero_kills).max
      appearance.hero_kills == max_hero_kills
    end
  end

  def times_top_unit_kills_with_faction(faction)
    appearances.includes(:match).where(faction: faction).count do |appearance|
      next false unless appearance.unit_kills.present?

      match = appearance.match
      player_good = faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.unit_kills.present?
      end

      next false if team_appearances.empty?

      max_unit_kills = team_appearances.map(&:unit_kills).max
      appearance.unit_kills == max_unit_kills
    end
  end

  def avg_hero_kill_contribution_with_faction(faction)
    contributions = []
    appearances.includes(:match).where(faction: faction).each do |appearance|
      next unless appearance.hero_kills.present?

      match = appearance.match
      player_good = faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.hero_kills.present?
      end

      team_total = team_appearances.sum(&:hero_kills)
      next if team_total.zero?

      contributions << (appearance.hero_kills.to_f / team_total * 100)
    end

    return 0 if contributions.empty?
    (contributions.sum / contributions.size).round(1)
  end

  def avg_unit_kill_contribution_with_faction(faction)
    contributions = []
    appearances.includes(:match).where(faction: faction).each do |appearance|
      next unless appearance.unit_kills.present?

      match = appearance.match
      player_good = faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.unit_kills.present?
      end

      team_total = team_appearances.sum(&:unit_kills)
      next if team_total.zero?

      contributions << (appearance.unit_kills.to_f / team_total * 100)
    end

    return 0 if contributions.empty?
    (contributions.sum / contributions.size).round(1)
  end

  def observation_count
    Wc3statsReplay.all.count do |replay|
      replay.players.any? do |p|
        p["name"] == battletag && (p["slot"].nil? || p["slot"] > 9 || p["isWinner"].nil?)
      end
    end
  end

  def wins_as_underdog
    count_matches_by_role(:underdog, :win)
  end

  def losses_as_underdog
    count_matches_by_role(:underdog, :loss)
  end

  def wins_as_favorite
    count_matches_by_role(:favorite, :win)
  end

  def losses_as_favorite
    count_matches_by_role(:favorite, :loss)
  end

  def avg_underdog_elo_difference
    diffs = elo_differences_by_role(:underdog)
    return 0 if diffs.empty?
    (diffs.sum / diffs.size).round(0)
  end

  def avg_favorite_elo_difference
    diffs = elo_differences_by_role(:favorite)
    return 0 if diffs.empty?
    (diffs.sum / diffs.size).round(0)
  end

  def times_top_hero_kills_on_team
    appearances.includes(:match, :faction).count do |appearance|
      next false unless appearance.hero_kills.present?

      match = appearance.match
      player_good = appearance.faction.good?

      # Get teammates' appearances (same side)
      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.hero_kills.present?
      end

      next false if team_appearances.empty?

      max_hero_kills = team_appearances.map(&:hero_kills).max
      appearance.hero_kills == max_hero_kills
    end
  end

  def times_top_unit_kills_on_team
    appearances.includes(:match, :faction).count do |appearance|
      next false unless appearance.unit_kills.present?

      match = appearance.match
      player_good = appearance.faction.good?

      # Get teammates' appearances (same side)
      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.unit_kills.present?
      end

      next false if team_appearances.empty?

      max_unit_kills = team_appearances.map(&:unit_kills).max
      appearance.unit_kills == max_unit_kills
    end
  end

  def avg_hero_kill_contribution
    contributions = []
    appearances.includes(:match, :faction).each do |appearance|
      next unless appearance.hero_kills.present?

      match = appearance.match
      player_good = appearance.faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.hero_kills.present?
      end

      team_total = team_appearances.sum(&:hero_kills)
      next if team_total.zero?

      contributions << (appearance.hero_kills.to_f / team_total * 100)
    end

    return 0 if contributions.empty?
    (contributions.sum / contributions.size).round(1)
  end

  def avg_unit_kill_contribution
    contributions = []
    appearances.includes(:match, :faction).each do |appearance|
      next unless appearance.unit_kills.present?

      match = appearance.match
      player_good = appearance.faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.unit_kills.present?
      end

      team_total = team_appearances.sum(&:unit_kills)
      next if team_total.zero?

      contributions << (appearance.unit_kills.to_f / team_total * 100)
    end

    return 0 if contributions.empty?
    (contributions.sum / contributions.size).round(1)
  end

  private

  def elo_differences_by_role(role)
    differences = []
    appearances.includes(:match, :faction).each do |appearance|
      next unless appearance.elo_rating

      match = appearance.match
      player_good = appearance.faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.elo_rating.present?
      end

      opponent_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? != player_good && a.elo_rating.present?
      end

      next if team_appearances.empty? || opponent_appearances.empty?

      team_avg_elo = team_appearances.sum(&:elo_rating).to_f / team_appearances.size
      opponent_avg_elo = opponent_appearances.sum(&:elo_rating).to_f / opponent_appearances.size
      elo_diff = team_avg_elo - opponent_avg_elo
      is_underdog = elo_diff < 0

      if (role == :underdog && is_underdog) || (role == :favorite && !is_underdog)
        differences << elo_diff.abs
      end
    end
    differences
  end

  def count_matches_by_role(role, outcome)
    appearances.includes(:match, :faction).count do |appearance|
      next false unless appearance.elo_rating

      match = appearance.match
      player_good = appearance.faction.good?

      # Get team appearances (same side as player)
      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.elo_rating.present?
      end

      # Get opponent team appearances
      opponent_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? != player_good && a.elo_rating.present?
      end

      next false if team_appearances.empty? || opponent_appearances.empty?

      team_avg_elo = team_appearances.sum(&:elo_rating).to_f / team_appearances.size
      opponent_avg_elo = opponent_appearances.sum(&:elo_rating).to_f / opponent_appearances.size
      is_underdog = team_avg_elo < opponent_avg_elo

      # Determine if player won
      player_won = (player_good && match.good_victory?) || (!player_good && !match.good_victory?)

      role_matches = (role == :underdog) ? is_underdog : !is_underdog
      outcome_matches = (outcome == :win) ? player_won : !player_won

      role_matches && outcome_matches
    end
  end
end
