# Everything the lobby edit page needs about players: lifetime records, faction
# stats, contribution ranks, and the search list.
#
# Expensive to compute, so it is cached globally - it does not depend on which
# lobby is being edited. Both LobbiesController and CachePrebuildJob read it
# through .fetch, so the prebuilt entry is the one the page actually uses.
class LobbyEditStats
  # "v4": search entries gained recentGames / lastSeen / defaultRank / form / recentLeaves
  CACHE_VERSION = "v4"
  CACHE_TTL = 1.hour

  # How many players each source contributes to the default search list, and
  # how many survive the interleave
  DEFAULT_SEARCH_SOURCE_SIZE = 30
  DEFAULT_SEARCH_LIST_SIZE = 40

  # With an empty search box the list shows two kinds of player, alternating:
  # whoever played most recently, and whoever has played the most in the last
  # three months. Returns player_id => position, for players in the list.
  def default_search_ranks(last_played, games_last_3_months)
    by_recency = last_played.compact.sort_by { |_, played_at| played_at.to_s }.reverse
                            .first(DEFAULT_SEARCH_SOURCE_SIZE).map(&:first)
    by_activity = games_last_3_months.sort_by { |_, games| -games }
                                     .first(DEFAULT_SEARCH_SOURCE_SIZE).map(&:first)

    longest = [ by_recency.size, by_activity.size ].max
    interleaved = (0...longest).flat_map { |i| [ by_recency[i], by_activity[i] ] }.compact.uniq

    interleaved.first(DEFAULT_SEARCH_LIST_SIZE).each_with_index.to_h
  end

  def format_last_seen(played_at)
    return nil if played_at.blank?

    time = played_at.is_a?(String) ? Time.zone.parse(played_at) : played_at
    time&.strftime("%b %d")
  rescue ArgumentError
    nil
  end

  def self.cache_key
    [ "lobby_edit_player_stats", CACHE_VERSION, StatsCacheKey.key ]
  end

  def self.fetch
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { new.call }
  end

  def call
    player_stats = {}

    # Get all wins (good team + good_victory OR evil team + evil_victory)
    wins_good = Appearance.joins(:match, :faction)
      .where(factions: { good: true }, matches: { good_victory: true, ignored: false })
      .group(:player_id).count

    wins_evil = Appearance.joins(:match, :faction)
      .where(factions: { good: false }, matches: { good_victory: false, ignored: false })
      .group(:player_id).count

    # Get total matches per player (only non-ignored)
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

    # Who has played most recently, and who has played the most lately - the
    # two ways someone ends up in the default search list
    last_played = Appearance.joins(:match)
      .where(matches: { ignored: false })
      .group(:player_id)
      .maximum("matches.played_at")

    games_last_3_months = Appearance.joins(:match)
      .where(matches: { ignored: false })
      .where("matches.played_at >= ?", 3.months.ago)
      .group(:player_id).count

    default_ranks = default_search_ranks(last_played, games_last_3_months)
    form_by_player = PlayerForm.recent
    leaves_by_player = PlayerForm.recent_leaves

    # Build player search data with games played count and avg rank
    players_search_data = players_for_select.map do |player|
      stats = player_stats[player[:id]] || { wins: 0, losses: 0 }
      games = stats[:wins] + stats[:losses]
      played_at = last_played[player[:id]]
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
        gamesLeft: player[:games_left] || 0,
        recentGames: games_last_3_months[player[:id]] || 0,
        form: form_by_player[player[:id]] || [],
        recentLeaves: leaves_by_player[player[:id]] || 0,
        lastSeen: format_last_seen(played_at),
        defaultRank: default_ranks[player[:id]]
      }
    end.sort_by { |p| -p[:games] } # Sort by most games first

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
      player_faction_stats: player_faction_stats,
      faction_totals: faction_totals_count
    }
  end
end
