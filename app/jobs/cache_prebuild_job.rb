# frozen_string_literal: true

class CachePrebuildJob < ApplicationJob
  queue_as :low

  # Prebuild caches for a match and its participants
  # @param match_id [Integer] The match ID to prebuild caches for
  def perform(match_id)
    match = Match.find_by(id: match_id)
    return unless match

    Rails.logger.info "CachePrebuildJob: Starting cache prebuild for match ##{match_id}"

    # Get players and factions from this match
    appearances = match.appearances.includes(:player, :faction)
    player_ids = appearances.map(&:player_id).compact.uniq
    faction_ids = appearances.map(&:faction_id).compact.uniq

    # Prebuild player caches
    prebuild_player_caches(player_ids)

    # Prebuild faction caches
    prebuild_faction_caches(faction_ids)

    # Prebuild global rank caches (used by all player pages)
    prebuild_rank_caches

    # Prebuild home page caches
    prebuild_home_caches

    # Prebuild lobby edit cache (used by all lobby edits)
    prebuild_lobby_edit_cache

    Rails.logger.info "CachePrebuildJob: Completed cache prebuild for match ##{match_id}"
  end

  # Prebuild caches for specific players
  def self.prebuild_for_players(player_ids)
    return if player_ids.blank?

    new.send(:prebuild_player_caches, player_ids)
    new.send(:prebuild_rank_caches)
  end

  # Prebuild caches for specific factions
  def self.prebuild_for_factions(faction_ids)
    return if faction_ids.blank?

    new.send(:prebuild_faction_caches, faction_ids)
  end

  private

  def prebuild_player_caches(player_ids)
    players = Player.where(id: player_ids)
    players.each do |player|
      prebuild_player_cache(player)
    end
    Rails.logger.info "CachePrebuildJob: Prebuilt caches for #{players.size} players"
  end

  def prebuild_player_cache(player)
    # Get player-specific cache version
    player_last_match = player.appearances.joins(:match).maximum("matches.updated_at")
    player_cache_version = player_last_match&.to_i || 0
    cache_key = [ "player_stats", player.id, nil, player_cache_version ]

    # Prebuild basic stats (using same logic as PlayersController#show)
    appearances = player.appearances
      .joins(:match)
      .where(matches: { ignored: false, has_early_leaver: false })
      .includes(:faction, match: { appearances: :faction })
      .merge(Match.reverse_chronological)

    Rails.cache.fetch(cache_key + [ "basic" ]) do
      stats = PlayerStatsCalculator.new(player, appearances).compute
      # Convert Hash with default proc to regular Hash for caching
      stats[:faction_stats] = Hash[stats[:faction_stats]] if stats[:faction_stats]
      stats
    end

    # Prebuild event stats
    Rails.cache.fetch(cache_key + [ "events" ]) do
      PlayerEventStatsCalculator.new(player, map_versions: nil).compute
    end
  rescue => e
    Rails.logger.warn "CachePrebuildJob: Error prebuilding cache for player #{player.id}: #{e.message}"
  end

  def prebuild_faction_caches(faction_ids)
    factions = Faction.where(id: faction_ids)
    factions.each do |faction|
      prebuild_faction_cache(faction)
    end
    Rails.logger.info "CachePrebuildJob: Prebuilt caches for #{factions.size} factions"
  end

  def prebuild_faction_cache(faction)
    # Get faction-specific cache version
    faction_last_match = faction.appearances.joins(:match).maximum("matches.updated_at")
    faction_cache_version = faction_last_match&.to_i || 0
    cache_key = [ "faction_stats", faction.id, nil, faction_cache_version ]

    # Prebuild basic stats
    Rails.cache.fetch(cache_key + [ "basic" ]) do
      FactionStatsCalculator.new(faction).compute
    end

    # Prebuild event stats
    Rails.cache.fetch(cache_key + [ "events" ]) do
      FactionEventStatsCalculator.new(faction).compute
    end

    # Prebuild top performers
    Rails.cache.fetch(cache_key + [ "top_performers" ]) do
      PlayerFactionStat.where(faction: faction)
        .where("games_played >= ?", PlayerFactionStatsCalculator::MIN_GAMES_FOR_RANKING)
        .where.not(faction_score: nil)
        .order(faction_score: :desc)
        .limit(10)
        .includes(:player)
        .to_a
    end

    # Prebuild top rank players
    Rails.cache.fetch(cache_key + [ "top_rank_players" ]) do
      eligible_player_ids = Appearance.joins(:match)
        .where(faction_id: faction.id, matches: { ignored: false })
        .where.not(contribution_rank: nil)
        .group(:player_id)
        .having("COUNT(*) >= ?", PlayerFactionStatsCalculator::MIN_GAMES_FOR_RANKING)
        .pluck(:player_id)

      avg_ranks = Appearance.joins(:match)
        .where(player_id: eligible_player_ids, faction_id: faction.id, matches: { ignored: false })
        .where.not(contribution_rank: nil)
        .group(:player_id)
        .pluck(:player_id, Arel.sql("AVG(contribution_rank)"), Arel.sql("COUNT(*)"))
        .map { |pid, avg, count| { player_id: pid, avg_rank: avg.to_f.round(2), games: count } }
        .sort_by { |d| d[:avg_rank] }
        .first(10)

      player_ids = avg_ranks.map { |d| d[:player_id] }
      players_by_id = Player.where(id: player_ids).index_by(&:id)

      avg_ranks.map { |d| d.merge(player: players_by_id[d[:player_id]]) }
    end
  rescue => e
    Rails.logger.warn "CachePrebuildJob: Error prebuilding cache for faction #{faction.id}: #{e.message}"
  end

  def prebuild_rank_caches
    # Prebuild global rank data that's used by player show pages
    # These are cached with StatsCacheKey which is global

    # CR ranks
    Rails.cache.fetch([ "cr_ranks", StatsCacheKey.key ]) do
      ranks = {}
      Player.joins(:matches)
        .where(matches: { ignored: false })
        .where.not(players: { custom_rating: nil })
        .distinct
        .order(custom_rating: :desc)
        .pluck(:id)
        .each_with_index { |id, idx| ranks[id] = idx + 1 }
      ranks
    end

    # ML ranks
    Rails.cache.fetch([ "ml_ranks", StatsCacheKey.key ]) do
      ranks = {}
      Player.joins(:matches)
        .where(matches: { ignored: false })
        .where.not(players: { ml_score: nil })
        .distinct
        .order(ml_score: :desc)
        .pluck(:id)
        .each_with_index { |id, idx| ranks[id] = idx + 1 }
      ranks
    end

    # Faction totals (for percentile calculations)
    Rails.cache.fetch([ "faction_totals", StatsCacheKey.key ]) do
      PlayerFactionStat.where.not(faction_score: nil).group(:faction_id).count
    end

    Rails.logger.info "CachePrebuildJob: Prebuilt global rank caches"
  rescue => e
    Rails.logger.warn "CachePrebuildJob: Error prebuilding rank caches: #{e.message}"
  end

  def prebuild_home_caches
    # Prebuild home page counts
    Rails.cache.fetch([ "home_counts", StatsCacheKey.key ]) do
      matches_count = Match.where(ignored: false).count
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

    # Prebuild recent matches
    Rails.cache.fetch([ "home_recent_matches", StatsCacheKey.key ]) do
      Match.where(ignored: false)
        .order(uploaded_at: :desc)
        .includes(appearances: [ :player, :faction ])
        .limit(3)
        .to_a
    end

    Rails.logger.info "CachePrebuildJob: Prebuilt home page caches"
  rescue => e
    Rails.logger.warn "CachePrebuildJob: Error prebuilding home caches: #{e.message}"
  end

  def prebuild_lobby_edit_cache
    cache_key = [ "lobby_edit_player_stats", StatsCacheKey.key ]

    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      compute_lobby_edit_stats
    end

    Rails.logger.info "CachePrebuildJob: Prebuilt lobby edit cache"
  rescue => e
    Rails.logger.warn "CachePrebuildJob: Error prebuilding lobby edit cache: #{e.message}"
  end

  def compute_lobby_edit_stats
    player_stats = {}

    # Get all wins (good team + good_victory OR evil team + evil_victory)
    wins_good = Appearance.joins(:match, :faction)
      .where(factions: { good: true }, matches: { good_victory: true, ignored: false })
      .group(:player_id).count

    wins_evil = Appearance.joins(:match, :faction)
      .where(factions: { good: false }, matches: { good_victory: false, ignored: false })
      .group(:player_id).count

    # Get total matches per player
    total_matches = Appearance.joins(:match)
      .where(matches: { ignored: false })
      .group(:player_id).count

    # Only iterate players with matches (not ALL players)
    total_matches.each do |player_id, total|
      wins = (wins_good[player_id] || 0) + (wins_evil[player_id] || 0)
      player_stats[player_id] = { wins: wins, losses: total - wins }
    end

    # Precompute faction-specific W/L for all players
    faction_stats = {}
    faction_wins = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false })
      .where("(factions.good = ? AND matches.good_victory = ?) OR (factions.good = ? AND matches.good_victory = ?)", true, true, false, false)
      .group(:player_id, :faction_id).count

    faction_totals = Appearance.joins(:match)
      .where(matches: { ignored: false })
      .group(:player_id, :faction_id).count

    faction_totals.each do |(player_id, faction_id), total|
      faction_stats[[ player_id, faction_id ]] = {
        wins: faction_wins[[ player_id, faction_id ]] || 0,
        losses: total - (faction_wins[[ player_id, faction_id ]] || 0)
      }
    end

    players_for_select = Player.order(:nickname).pluck(:id, :nickname, :alternative_name, :ml_score, :custom_rating, :leave_pct, :games_left)
      .map { |id, nn, an, ml, cr, lp, gl| { id: id, nickname: nn, alternative_name: an, ml_score: ml, custom_rating: cr, leave_pct: lp, games_left: gl } }

    # Precompute average contribution ranks for all players
    avg_ranks = Appearance.joins(:match)
      .where(matches: { ignored: false })
      .where.not(contribution_rank: nil)
      .group(:player_id)
      .average(:contribution_rank)
      .transform_values(&:to_f)

    # Precompute faction-specific avg ranks and counts
    faction_rank_data = Appearance.joins(:match)
      .where(matches: { ignored: false })
      .where.not(contribution_rank: nil)
      .group(:player_id, :faction_id)
      .pluck(:player_id, :faction_id, Arel.sql("AVG(contribution_rank)"), Arel.sql("COUNT(*)"))

    faction_rank_stats = {}
    faction_rank_data.each do |player_id, faction_id, avg_rank, count|
      faction_rank_stats[[ player_id, faction_id ]] = { avg: avg_rank.to_f, count: count }
    end

    # Precompute faction-specific performance scores from PlayerFactionStat
    faction_perf_stats = {}
    PlayerFactionStat.where.not(faction_score: nil).pluck(:player_id, :faction_id, :faction_score).each do |player_id, faction_id, score|
      faction_perf_stats[[ player_id, faction_id ]] = score.round
    end

    # Build player search data with games played count and avg rank
    players_search_data = players_for_select.map do |player|
      stats = player_stats[player[:id]] || { wins: 0, losses: 0 }
      games = stats[:wins] + stats[:losses]
      {
        id: player[:id],
        nickname: player[:nickname],
        alternativeName: player[:alternative_name],
        customRating: player[:custom_rating]&.round || 1300,
        mlScore: player[:ml_score],
        avgRank: avg_ranks[player[:id]]&.round(2) || 4.0,
        wins: stats[:wins],
        losses: stats[:losses],
        games: games,
        leavePct: player[:leave_pct]&.round || 0,
        gamesLeft: player[:games_left] || 0
      }
    end.sort_by { |p| -p[:games] }

    # Get 28 most recent players based on their latest match
    recent_player_ids = Appearance.joins(:match)
                                  .where(matches: { ignored: false })
                                  .group(:player_id)
                                  .order(Arel.sql("MAX(matches.uploaded_at) DESC"))
                                  .limit(28)
                                  .pluck(:player_id)

    recent_players_data = Player.where(id: recent_player_ids)
                                .pluck(:id, :nickname, :alternative_name, :ml_score, :custom_rating)
                                .index_by(&:first)

    # Get last match date for each player
    last_match_dates = Appearance.joins(:match)
                                 .where(player_id: recent_player_ids, matches: { ignored: false })
                                 .group(:player_id)
                                 .pluck(:player_id, Arel.sql("MAX(matches.uploaded_at)"))
                                 .to_h

    recent_players = recent_player_ids.filter_map do |player_id|
      data = recent_players_data[player_id]
      next unless data
      id, nickname, alternative_name, ml_score, custom_rating = data
      stats = player_stats[id] || { wins: 0, losses: 0 }
      last_date = last_match_dates[id]
      formatted_date = if last_date.is_a?(String)
                         Time.parse(last_date).strftime("%b %d") rescue last_date[5, 5]
      elsif last_date.respond_to?(:strftime)
                         last_date.strftime("%b %d")
      end
      {
        id: id,
        nickname: nickname,
        alternativeName: alternative_name,
        mlScore: ml_score,
        avgRank: avg_ranks[id]&.round(2) || 4.0,
        customRating: custom_rating&.round || 1300,
        wins: stats[:wins],
        losses: stats[:losses],
        lastSeen: formatted_date
      }
    end

    # Preload PlayerFactionStats for faction-specific ratings/scores
    player_faction_stats = PlayerFactionStat.all.index_by { |pfs| [ pfs.player_id, pfs.faction_id ] }

    # Get totals per faction for percentile calculation
    faction_totals_count = PlayerFactionStat.where.not(faction_score: nil).group(:faction_id).count

    {
      player_stats: player_stats,
      faction_stats: faction_stats,
      players_for_select: players_for_select,
      faction_rank_stats: faction_rank_stats,
      faction_perf_stats: faction_perf_stats,
      players_search_data: players_search_data,
      recent_players: recent_players,
      player_faction_stats: player_faction_stats,
      faction_totals: faction_totals_count
    }
  end
end
