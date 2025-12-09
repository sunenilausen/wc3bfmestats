class LobbiesController < ApplicationController
  before_action :set_lobby, only: %i[ show edit update balance ]
  before_action :ensure_lobby_owner, only: %i[ edit update balance ]

  # GET /lobbies or /lobbies.json
  def index
    @lobbies = Lobby.includes(lobby_players: [ :faction, :player ]).order(updated_at: :desc)
  end

  # GET /lobbies/1 or /lobbies/1.json
  def show
    # Cache key based on lobby composition and global stats version
    player_ids = @lobby.lobby_players.map(&:player_id).compact.sort
    observer_ids = @lobby.observer_ids.sort
    cache_key = [ "lobby_stats", @lobby.id, player_ids, observer_ids, StatsCacheKey.key ]

    cached_stats = Rails.cache.fetch(cache_key) do
      preload_lobby_player_stats
      preload_event_stats
      compute_score_prediction
      {
        lobby_player_stats: @lobby_player_stats,
        faction_specific_stats: @faction_specific_stats,
        recent_stats: @recent_stats,
        event_stats: @event_stats,
        player_scores: @player_scores,
        score_prediction: @score_prediction,
        feature_contributions: @feature_contributions,
        overall_avg_ranks: @overall_avg_ranks,
        faction_rank_data: @faction_rank_data,
        faction_perf_stats: @faction_perf_stats
      }
    end

    @lobby_player_stats = cached_stats[:lobby_player_stats]
    @faction_specific_stats = cached_stats[:faction_specific_stats]
    @recent_stats = cached_stats[:recent_stats]
    @event_stats = cached_stats[:event_stats]
    @player_scores = cached_stats[:player_scores]
    @score_prediction = cached_stats[:score_prediction]
    @feature_contributions = cached_stats[:feature_contributions]
    @overall_avg_ranks = cached_stats[:overall_avg_ranks]
    @faction_rank_data = cached_stats[:faction_rank_data]
    @faction_perf_stats = cached_stats[:faction_perf_stats]

    # Get historical accuracy for the current prediction confidence level
    if @score_prediction
      confidence_pct = [@score_prediction[:good_win_pct], @score_prediction[:evil_win_pct]].max
      @prediction_accuracy = PredictionAccuracyCache.accuracy_for(confidence_pct)
    end
  end

  # GET /lobbies/new - creates lobby instantly with previous match players
  def new
    @lobby = Lobby.new
    @lobby.session_token = lobby_session_token
    latest_match = Match.order(uploaded_at: :desc).first

    Faction.order(:id).each do |faction|
      # Find player from latest match who played this faction
      player_id = latest_match&.appearances&.find_by(faction: faction)&.player_id
      @lobby.lobby_players.build(faction: faction, player_id: player_id)
    end

    if @lobby.save
      redirect_to edit_lobby_path(@lobby)
    else
      # Fallback to showing the form if save fails
      preload_player_stats
      render :new
    end
  end

  # GET /lobbies/1/edit
  def edit
    # Ensure all factions have a lobby_player
    existing_faction_ids = @lobby.lobby_players.map(&:faction_id)
    Faction.all.each do |faction|
      unless existing_faction_ids.include?(faction.id)
        @lobby.lobby_players.build(faction: faction)
      end
    end

    preload_player_stats
    @new_player_defaults = NewPlayerDefaults.all

    # Provide prediction accuracy by confidence bucket for JavaScript
    @prediction_accuracy_buckets = PredictionAccuracyCache.all

    # Get last match data for "Last Match" button (most recently uploaded non-ignored match)
    @last_match = Match.includes(appearances: [ :faction, :player ])
                       .where(ignored: false)
                       .order(uploaded_at: :desc)
                       .first
    @last_match_players = {}
    if @last_match
      @last_match.appearances.each do |appearance|
        @last_match_players[appearance.faction_id] = appearance.player_id
      end
    end
  end

  # POST /lobbies or /lobbies.json
  def create
    @lobby = Lobby.new

    # Handle lobby_players manually
    if params[:lobby] && params[:lobby][:lobby_players_attributes]
      params[:lobby][:lobby_players_attributes].each do |_, attrs|
        player_id = attrs[:player_id].presence
        @lobby.lobby_players.build(
          faction_id: attrs[:faction_id],
          player_id: player_id
        )
      end
    end

    # Handle observers
    if params[:lobby] && params[:lobby][:observer_ids]
      @lobby.observer_ids = params[:lobby][:observer_ids].reject(&:blank?)
    end

    respond_to do |format|
      if @lobby.save
        format.html { redirect_to @lobby, notice: "Lobby was successfully created." }
        format.json { render :show, status: :created, location: @lobby }
      else
        Faction.all.each { |f| @lobby.lobby_players.build(faction: f) unless @lobby.lobby_players.any? { |lp| lp.faction_id == f.id } }
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @lobby.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /lobbies/1 or /lobbies/1.json
  def update
    # Handle lobby_players manually
    if params[:lobby] && params[:lobby][:lobby_players_attributes]
      params[:lobby][:lobby_players_attributes].each do |_, attrs|
        lobby_player = @lobby.lobby_players.find_by(id: attrs[:id]) ||
                       @lobby.lobby_players.find_by(faction_id: attrs[:faction_id]) ||
                       @lobby.lobby_players.build(faction_id: attrs[:faction_id])

        # Keep the slot but clear the player if blank
        lobby_player.player_id = attrs[:player_id].presence
        # Handle is_new_player flag
        lobby_player.is_new_player = attrs[:is_new_player] == "true" || attrs[:is_new_player] == "1"
        lobby_player.save
      end
    end

    # Handle observers
    if params[:lobby]
      @lobby.observer_ids = (params[:lobby][:observer_ids] || []).reject(&:blank?)
    end

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to edit_lobby_path(@lobby), status: :see_other }
      format.json { render :show, status: :ok, location: @lobby }
    end
  end

  # POST /lobbies/1/balance
  def balance
    result = LobbyBalancer.new(@lobby).balance!

    respond_to do |format|
      format.json { render json: result }
      format.html { redirect_to edit_lobby_path(@lobby), notice: result[:message] }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_lobby
      @lobby = Lobby.includes(lobby_players: [ :faction, :player ], observers: []).find(params.expect(:id))
    end

    # Check if current session owns this lobby
    def ensure_lobby_owner
      unless @lobby.session_token == lobby_session_token
        redirect_to @lobby, alert: "You can only edit lobbies you created."
      end
    end

    # Get or create a unique session token for lobby ownership
    def lobby_session_token
      session[:lobby_token] ||= SecureRandom.hex(16)
    end

    # Make this available to views
    helper_method :lobby_owner?
    def lobby_owner?(lobby = @lobby)
      lobby&.session_token == lobby_session_token
    end

    # Only allow a list of trusted parameters through.
    def lobby_params
      params.fetch(:lobby, {})
    end

    def preload_player_stats
      # Precompute wins for all players in 2 queries instead of N*2
      @player_stats = {}

      # Get all wins (good team + good_victory OR evil team + evil_victory)
      wins_good = Appearance.joins(:match, :faction)
        .where(factions: { good: true }, matches: { good_victory: true })
        .group(:player_id).count

      wins_evil = Appearance.joins(:match, :faction)
        .where(factions: { good: false }, matches: { good_victory: false })
        .group(:player_id).count

      # Get total matches per player
      total_matches = Appearance.group(:player_id).count

      Player.pluck(:id).each do |player_id|
        wins = (wins_good[player_id] || 0) + (wins_evil[player_id] || 0)
        total = total_matches[player_id] || 0
        @player_stats[player_id] = { wins: wins, losses: total - wins }
      end

      # Precompute faction-specific W/L for all players
      @faction_stats = {}
      faction_wins = Appearance.joins(:match, :faction)
        .where("(factions.good = ? AND matches.good_victory = ?) OR (factions.good = ? AND matches.good_victory = ?)", true, true, false, false)
        .group(:player_id, :faction_id).count

      faction_totals = Appearance.group(:player_id, :faction_id).count

      faction_totals.each do |(player_id, faction_id), total|
        @faction_stats[[ player_id, faction_id ]] = {
          wins: faction_wins[[ player_id, faction_id ]] || 0,
          losses: total - (faction_wins[[ player_id, faction_id ]] || 0)
        }
      end

      @players_for_select = Player.order(:nickname).select(:id, :nickname, :alternative_name, :ml_score, :custom_rating, :leave_pct, :games_left)

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

      @faction_rank_stats = {}
      faction_rank_data.each do |player_id, faction_id, avg_rank, count|
        @faction_rank_stats[[ player_id, faction_id ]] = { avg: avg_rank.to_f, count: count }
      end

      # Precompute faction-specific performance scores from PlayerFactionStat
      @faction_perf_stats = {}
      PlayerFactionStat.where.not(faction_score: nil).pluck(:player_id, :faction_id, :faction_score).each do |player_id, faction_id, score|
        @faction_perf_stats[[ player_id, faction_id ]] = score.round
      end

      # Build player search data with games played count and avg rank
      @players_search_data = @players_for_select.map do |player|
        stats = @player_stats[player.id] || { wins: 0, losses: 0 }
        games = stats[:wins] + stats[:losses]
        {
          id: player.id,
          nickname: player.nickname,
          alternativeName: player.alternative_name,
          customRating: player.custom_rating&.round || 1300,
          mlScore: player.ml_score,
          avgRank: avg_ranks[player.id]&.round(2) || 4.0,
          wins: stats[:wins],
          losses: stats[:losses],
          games: games,
          leavePct: player.leave_pct&.round || 0,
          gamesLeft: player.games_left || 0
        }
      end.sort_by { |p| -p[:games] } # Sort by most games first

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

      @recent_players = recent_player_ids.map do |player_id|
        data = recent_players_data[player_id]
        next unless data
        id, nickname, alternative_name, ml_score, custom_rating = data
        stats = @player_stats[id] || { wins: 0, losses: 0 }
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
      end.compact

      # Preload PlayerFactionStats for faction-specific ratings/scores
      @player_faction_stats = PlayerFactionStat
        .where(player_id: Player.pluck(:id))
        .index_by { |pfs| [ pfs.player_id, pfs.faction_id ] }

      # Get totals per faction for percentile calculation
      @faction_totals = PlayerFactionStat.where.not(faction_score: nil).group(:faction_id).count
    end

    def preload_lobby_player_stats
      # Get all player IDs from this lobby (players + observers)
      player_ids = @lobby.lobby_players.map(&:player_id).compact
      player_ids += @lobby.observer_ids
      player_ids.uniq!

      @lobby_player_stats = {}
      @faction_specific_stats = {}
      @recent_stats = {}
      @overall_avg_ranks = {}
      @faction_rank_data = {}
      @faction_perf_stats = {}
      return if player_ids.empty?

      # Preload players in one query
      players_by_id = Player.where(id: player_ids).index_by(&:id)

      # Preload overall average ranks
      @overall_avg_ranks = Appearance.joins(:match)
        .where(player_id: player_ids, matches: { ignored: false })
        .where.not(contribution_rank: nil)
        .group(:player_id)
        .average(:contribution_rank)
        .transform_values(&:to_f)

      # Preload faction-specific avg ranks and counts
      faction_rank_data = Appearance.joins(:match)
        .where(player_id: player_ids, matches: { ignored: false })
        .where.not(contribution_rank: nil)
        .group(:player_id, :faction_id)
        .pluck(:player_id, :faction_id, Arel.sql("AVG(contribution_rank)"), Arel.sql("COUNT(*)"))

      faction_rank_data.each do |player_id, faction_id, avg_rank, count|
        @faction_rank_data[[ player_id, faction_id ]] = { avg: avg_rank.to_f, count: count }
      end

      # Preload faction-specific performance scores
      PlayerFactionStat.where(player_id: player_ids).where.not(faction_score: nil)
        .pluck(:player_id, :faction_id, :faction_score).each do |player_id, faction_id, score|
        @faction_perf_stats[[ player_id, faction_id ]] = score.round
      end

      # Preload all appearances with necessary associations in optimized queries
      # Filter out ignored matches
      appearances_by_player = Appearance
        .joins(:match)
        .includes(:faction, match: { appearances: :faction })
        .where(player_id: player_ids, matches: { ignored: false })
        .order("matches.uploaded_at DESC")
        .group_by(&:player_id)

      # Calculate recent stats cutoffs
      cutoff_100d = 100.days.ago
      cutoff_1y = 365.days.ago

      # Calculate stats for each player
      player_ids.each do |player_id|
        player = players_by_id[player_id]
        next unless player
        appearances = appearances_by_player[player_id] || []

        # Use PlayerStatsCalculator for main stats
        stats = PlayerStatsCalculator.new(player, appearances).compute
        # Convert Hash with default proc to regular Hash for caching
        stats[:faction_stats] = Hash[stats[:faction_stats]] if stats[:faction_stats]
        @lobby_player_stats[player_id] = stats

        # Calculate recent stats from preloaded appearances (avoid N+1)
        recent_100d = appearances.select { |a| a.match.uploaded_at && a.match.uploaded_at >= cutoff_100d }
        recent_100d_wins = recent_100d.count do |a|
          (a.faction.good? && a.match.good_victory?) || (!a.faction.good? && !a.match.good_victory?)
        end

        @recent_stats[player_id] = {
          recent_wins: recent_100d_wins,
          recent_losses: recent_100d.size - recent_100d_wins,
          faction_recent: {}
        }
      end

      # Calculate faction-specific recent stats for each lobby_player
      @lobby.lobby_players.each do |lp|
        next unless lp.player_id && lp.faction_id
        stats = @lobby_player_stats[lp.player_id]
        @faction_specific_stats[lp.id] = stats[:faction_stats][lp.faction_id] if stats

        # Calculate 1-year faction-specific stats
        appearances = appearances_by_player[lp.player_id] || []
        faction_apps_1y = appearances.select do |a|
          a.faction_id == lp.faction_id && a.match.uploaded_at && a.match.uploaded_at >= cutoff_1y
        end
        faction_wins_1y = faction_apps_1y.count do |a|
          (a.faction.good? && a.match.good_victory?) || (!a.faction.good? && !a.match.good_victory?)
        end

        @recent_stats[lp.player_id][:faction_recent][lp.faction_id] = {
          wins: faction_wins_1y,
          losses: faction_apps_1y.size - faction_wins_1y
        }
      end
    end

    def preload_event_stats
      # Get all player IDs from this lobby (players + observers)
      player_ids = @lobby.lobby_players.map(&:player_id).compact
      player_ids += @lobby.observer_ids
      player_ids.uniq!

      @event_stats = {}
      return if player_ids.empty?

      # Use batch calculator for all players at once (single pass through replays)
      @event_stats = BatchPlayerEventStatsCalculator.new(player_ids).compute
    end

    def compute_score_prediction
      predictor = LobbyWinPredictor.new(@lobby)
      @score_prediction = predictor.predict

      # Build player_scores hash for observers display
      @player_scores = {}
      @lobby.observer_ids.each do |observer_id|
        player = Player.find_by(id: observer_id)
        next unless player
        score_data = predictor.player_score(player)
        @player_scores[observer_id] = score_data if score_data
      end
    end
end
