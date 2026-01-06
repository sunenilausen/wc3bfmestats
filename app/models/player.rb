class Player < ApplicationRecord
  has_many :appearances
  has_many :matches, through: :appearances
  has_many :lobby_players
  has_many :lobbies, through: :lobby_players
  has_many :player_faction_stats, dependent: :destroy
  has_many :ranked_factions, through: :player_faction_stats, source: :faction

  # Always use battletag as URL param for consistency
  def to_param
    battletag.presence || id.to_s
  end

  # Find by battletag, nickname, or id (battletag first, then nickname, then id)
  # Also handles URL-encoded battletags (e.g., %23 for #) which can get double-encoded by browsers
  def self.find_by_battletag_or_id(param)
    return nil if param.blank?

    param_str = param.to_s

    # Try direct lookup first
    find_by(battletag: param_str) ||
      where("LOWER(nickname) = ?", param_str.downcase).first ||
      find_by(id: param_str) ||
      # If not found and param contains URL-encoded chars, try decoding
      (param_str.include?("%") && find_by(battletag: CGI.unescape(param_str)))
  end

  # Find player by battletag, checking both primary battletag and alternative_battletags
  # Used when importing replays to find merged players
  def self.find_by_any_battletag(battletag)
    return nil if battletag.blank?

    # First try exact match on primary battletag
    player = find_by(battletag: battletag)

    # If exact match found but battletag has no #, check if there's a better match with #
    # This handles cases where "BlackJacks" exists but "BlackJacks#11628" has more games
    if player && !battletag.include?("#")
      better_player = find_better_player_by_nickname(battletag, player)
      return better_player if better_player
    end

    return player if player

    # Then check alternative_battletags (for merged players)
    where("alternative_battletags IS NOT NULL AND alternative_battletags != '[]'").find_each do |p|
      return p if p.alternative_battletags&.include?(battletag)
    end

    # If no # in battletag, try to find by nickname with the most games
    # This handles cases like "ALPAPOLO" matching "ALPAPOLO#2858"
    unless battletag.include?("#")
      best = find_best_player_by_nickname(battletag)
      return best if best
    end

    # If battletag has #, check if there's a player with same nickname (without #)
    if battletag.include?("#")
      nickname = battletag.split("#").first
      existing = find_by(battletag: nickname)
      return existing if existing
    end

    nil
  end

  # Find the best player by nickname (one with most games)
  def self.find_best_player_by_nickname(nickname)
    # Find players with this nickname, prefer those with games
    players = where(nickname: nickname).to_a
    return nil if players.empty?

    # Sort by game count descending
    players_with_counts = players.map { |p| [ p, p.matches.where(ignored: false).count ] }
    players_with_counts.sort_by! { |_, count| -count }

    # Return player with most games, or first if none have games
    players_with_counts.first&.first
  end

  # Check if there's a better player match (with more games) for a nickname
  def self.find_better_player_by_nickname(nickname, current_player)
    current_games = current_player.matches.where(ignored: false).count

    # Find other players with same nickname but different battletag (with #)
    other_players = where(nickname: nickname).where.not(id: current_player.id).where("battletag LIKE ?", "%#%")

    other_players.each do |other|
      other_games = other.matches.where(ignored: false).count
      return other if other_games > current_games
    end

    nil
  end

  # Check if a player exists with this battletag (primary or alternative)
  def self.exists_by_any_battletag?(battletag)
    find_by_any_battletag(battletag).present?
  end

  # Returns the player's rank by custom rating (1 = highest)
  # Only counts players who have played at least one non-ignored match
  def cr_rank
    return nil unless custom_rating
    Player.joins(:matches)
      .where(matches: { ignored: false })
      .where.not(players: { custom_rating: nil })
      .where("players.custom_rating > ?", custom_rating)
      .distinct
      .count + 1
  end

  # Returns the player's rank by ML score (1 = highest)
  # Only counts players who have played at least one non-ignored match
  def ml_rank
    return nil unless ml_score
    Player.joins(:matches)
      .where(matches: { ignored: false })
      .where.not(players: { ml_score: nil })
      .where("players.ml_score > ?", ml_score)
      .distinct
      .count + 1
  end

  # Returns total number of ranked players (those with CR who played non-ignored matches)
  def self.ranked_player_count_by_cr
    Player.joins(:matches)
      .where(matches: { ignored: false })
      .where.not(players: { custom_rating: nil })
      .distinct
      .count
  end

  # Returns total number of ranked players (those with ML score who played non-ignored matches)
  def self.ranked_player_count_by_ml
    Player.joins(:matches)
      .where(matches: { ignored: false })
      .where.not(players: { ml_score: nil })
      .distinct
      .count
  end

  def last_seen
    matches.where(ignored: false).maximum(:uploaded_at)
  end

  def wins
    appearances.joins(:match, :faction)
      .where(matches: { ignored: false })
      .where(factions: { good: true }, matches: { good_victory: true })
      .or(appearances.joins(:match, :faction)
        .where(matches: { ignored: false })
        .where(factions: { good: false }, matches: { good_victory: false }))
      .count
  end

  def losses
    matches.where(ignored: false).count - wins
  end

  def recent_wins(days: 100)
    cutoff = days.days.ago
    appearances.joins(:match, :faction)
      .where(matches: { ignored: false, uploaded_at: cutoff.. })
      .where(factions: { good: true }, matches: { good_victory: true })
      .or(appearances.joins(:match, :faction)
        .where(matches: { ignored: false, uploaded_at: cutoff.. })
        .where(factions: { good: false }, matches: { good_victory: false }))
      .count
  end

  def recent_losses(days: 100)
    cutoff = days.days.ago
    recent_matches = matches.where(ignored: false, uploaded_at: cutoff..).count
    recent_matches - recent_wins(days: days)
  end

  def recent_wins_with_faction(faction, days: 100)
    cutoff = days.days.ago
    won = faction.good? ? true : false
    appearances.joins(:match)
      .where(faction: faction)
      .where(matches: { ignored: false, uploaded_at: cutoff.., good_victory: won })
      .count
  end

  def recent_losses_with_faction(faction, days: 100)
    cutoff = days.days.ago
    recent_with_faction = appearances.joins(:match)
      .where(faction: faction)
      .where(matches: { ignored: false, uploaded_at: cutoff.. })
      .count
    recent_with_faction - recent_wins_with_faction(faction, days: days)
  end

  def wins_with_faction(faction)
    won = faction.good? ? true : false
    appearances.joins(:match)
      .where(faction: faction)
      .where(matches: { ignored: false, good_victory: won })
      .count
  end

  def losses_with_faction(faction)
    total_with_faction = appearances.joins(:match).where(faction: faction, matches: { ignored: false }).count
    total_with_faction - wins_with_faction(faction)
  end

  def win_rate_with_faction(faction)
    total = appearances.joins(:match).where(faction: faction, matches: { ignored: false }).count
    return 0 if total.zero?
    (wins_with_faction(faction).to_f / total * 100).round(1)
  end

  def times_top_hero_kills_with_faction(faction)
    appearances.includes(:match).where(faction: faction).where(matches: { ignored: false }).count do |appearance|
      next false if appearance.hero_kills.nil? || appearance.ignore_hero_kills?

      match = appearance.match
      player_good = faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && !a.hero_kills.nil? && !a.ignore_hero_kills?
      end

      next false if team_appearances.empty?

      max_hero_kills = team_appearances.map(&:hero_kills).max
      appearance.hero_kills == max_hero_kills
    end
  end

  def times_top_unit_kills_with_faction(faction)
    appearances.includes(:match).where(faction: faction).where(matches: { ignored: false }).count do |appearance|
      next false unless appearance.unit_kills.present? && !appearance.ignore_unit_kills?

      match = appearance.match
      player_good = faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.unit_kills.present? && !a.ignore_unit_kills?
      end

      next false if team_appearances.empty?

      max_unit_kills = team_appearances.map(&:unit_kills).max
      appearance.unit_kills == max_unit_kills
    end
  end

  def avg_hero_kill_contribution_with_faction(faction)
    contributions = []
    appearances.includes(:match).where(faction: faction).where(matches: { ignored: false }).each do |appearance|
      next if appearance.hero_kills.nil? || appearance.ignore_hero_kills?

      match = appearance.match
      player_good = faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && !a.hero_kills.nil? && !a.ignore_hero_kills?
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
    appearances.includes(:match).where(faction: faction).where(matches: { ignored: false }).each do |appearance|
      next unless appearance.unit_kills.present? && !appearance.ignore_unit_kills?

      match = appearance.match
      player_good = faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.unit_kills.present? && !a.ignore_unit_kills?
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

  def avg_underdog_rating_difference
    diffs = rating_differences_by_role(:underdog)
    return 0 if diffs.empty?
    (diffs.sum / diffs.size).round(0)
  end

  def avg_favorite_rating_difference
    diffs = rating_differences_by_role(:favorite)
    return 0 if diffs.empty?
    (diffs.sum / diffs.size).round(0)
  end

  def times_top_hero_kills_on_team
    appearances.includes(:match, :faction).where(matches: { ignored: false }).count do |appearance|
      next false if appearance.hero_kills.nil? || appearance.ignore_hero_kills?

      match = appearance.match
      player_good = appearance.faction.good?

      # Get teammates' appearances (same side)
      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && !a.hero_kills.nil? && !a.ignore_hero_kills?
      end

      next false if team_appearances.empty?

      max_hero_kills = team_appearances.map(&:hero_kills).max
      appearance.hero_kills == max_hero_kills
    end
  end

  def times_top_unit_kills_on_team
    appearances.includes(:match, :faction).where(matches: { ignored: false }).count do |appearance|
      next false unless appearance.unit_kills.present? && !appearance.ignore_unit_kills?

      match = appearance.match
      player_good = appearance.faction.good?

      # Get teammates' appearances (same side)
      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.unit_kills.present? && !a.ignore_unit_kills?
      end

      next false if team_appearances.empty?

      max_unit_kills = team_appearances.map(&:unit_kills).max
      appearance.unit_kills == max_unit_kills
    end
  end

  def avg_hero_kill_contribution
    contributions = []
    appearances.includes(:match, :faction).where(matches: { ignored: false }).each do |appearance|
      next if appearance.hero_kills.nil? || appearance.ignore_hero_kills?

      match = appearance.match
      player_good = appearance.faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && !a.hero_kills.nil? && !a.ignore_hero_kills?
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
    appearances.includes(:match, :faction).where(matches: { ignored: false }).each do |appearance|
      next unless appearance.unit_kills.present? && !appearance.ignore_unit_kills?

      match = appearance.match
      player_good = appearance.faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.unit_kills.present? && !a.ignore_unit_kills?
      end

      team_total = team_appearances.sum(&:unit_kills)
      next if team_total.zero?

      contributions << (appearance.unit_kills.to_f / team_total * 100)
    end

    return 0 if contributions.empty?
    (contributions.sum / contributions.size).round(1)
  end

  private

  def rating_differences_by_role(role)
    differences = []
    appearances.includes(:match, :faction).where(matches: { ignored: false }).each do |appearance|
      next unless appearance.custom_rating

      match = appearance.match
      player_good = appearance.faction.good?

      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.custom_rating.present?
      end

      opponent_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? != player_good && a.custom_rating.present?
      end

      next if team_appearances.empty? || opponent_appearances.empty?

      team_avg_cr = team_appearances.sum(&:custom_rating).to_f / team_appearances.size
      opponent_avg_cr = opponent_appearances.sum(&:custom_rating).to_f / opponent_appearances.size
      cr_diff = team_avg_cr - opponent_avg_cr
      is_underdog = cr_diff < 0

      if (role == :underdog && is_underdog) || (role == :favorite && !is_underdog)
        differences << cr_diff.abs
      end
    end
    differences
  end

  def count_matches_by_role(role, outcome)
    appearances.includes(:match, :faction).where(matches: { ignored: false }).count do |appearance|
      next false unless appearance.custom_rating

      match = appearance.match
      player_good = appearance.faction.good?

      # Get team appearances (same side as player)
      team_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? == player_good && a.custom_rating.present?
      end

      # Get opponent team appearances
      opponent_appearances = match.appearances.includes(:faction).select do |a|
        a.faction.good? != player_good && a.custom_rating.present?
      end

      next false if team_appearances.empty? || opponent_appearances.empty?

      team_avg_cr = team_appearances.sum(&:custom_rating).to_f / team_appearances.size
      opponent_avg_cr = opponent_appearances.sum(&:custom_rating).to_f / opponent_appearances.size
      is_underdog = team_avg_cr < opponent_avg_cr

      # Determine if player won
      player_won = (player_good && match.good_victory?) || (!player_good && !match.good_victory?)

      role_matches = (role == :underdog) ? is_underdog : !is_underdog
      outcome_matches = (outcome == :win) ? player_won : !player_won

      role_matches && outcome_matches
    end
  end
end
