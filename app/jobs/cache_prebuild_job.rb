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
end
