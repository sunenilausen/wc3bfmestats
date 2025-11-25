class LobbiesController < ApplicationController
  before_action :set_lobby, only: %i[ show edit update destroy ]

  # GET /lobbies or /lobbies.json
  def index
    @lobbies = Lobby.all
  end

  # GET /lobbies/1 or /lobbies/1.json
  def show
    preload_lobby_player_stats
  end

  # GET /lobbies/new - creates lobby instantly with previous match players
  def new
    @lobby = Lobby.new
    latest_match = Match.order(played_at: :desc).first

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

        if attrs[:player_id].blank?
          lobby_player.destroy if lobby_player.persisted?
        else
          lobby_player.player_id = attrs[:player_id]
          lobby_player.save
        end
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

  # DELETE /lobbies/1 or /lobbies/1.json
  def destroy
    @lobby.destroy!

    respond_to do |format|
      format.html { redirect_to lobbies_path, notice: "Lobby was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_lobby
      @lobby = Lobby.includes(lobby_players: [:faction, :player], observers: []).find(params.expect(:id))
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

      @players_for_select = Player.order(:nickname).select(:id, :nickname, :elo_rating)

      # Build player search data with games played count
      @players_search_data = @players_for_select.map do |player|
        stats = @player_stats[player.id] || { wins: 0, losses: 0 }
        games = stats[:wins] + stats[:losses]
        {
          id: player.id,
          nickname: player.nickname,
          elo: player.elo_rating.round,
          wins: stats[:wins],
          losses: stats[:losses],
          games: games
        }
      end.sort_by { |p| -p[:games] } # Sort by most games first

      # Get unique players from last 5 matches (players and observers)
      recent_match_ids = Match.order(played_at: :desc).limit(5).pluck(:id)
      recent_player_ids = Appearance.where(match_id: recent_match_ids).distinct.pluck(:player_id)
      @recent_players = recent_player_ids.map do |pid|
        @players_search_data.find { |p| p[:id] == pid }
      end.compact
    end

    def preload_lobby_player_stats
      # Get all player IDs from this lobby (players + observers)
      player_ids = @lobby.lobby_players.map(&:player_id).compact
      player_ids += @lobby.observer_ids
      player_ids.uniq!

      @lobby_player_stats = {}
      @faction_specific_stats = {}
      @recent_stats = {}
      return if player_ids.empty?

      # Preload players in one query
      players_by_id = Player.where(id: player_ids).index_by(&:id)

      # Preload all appearances with necessary associations in optimized queries
      appearances_by_player = Appearance
        .includes(:faction, match: { appearances: :faction })
        .where(player_id: player_ids)
        .order("matches.played_at DESC")
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
        @lobby_player_stats[player_id] = PlayerStatsCalculator.new(player, appearances).compute

        # Calculate recent stats from preloaded appearances (avoid N+1)
        recent_100d = appearances.select { |a| a.match.played_at && a.match.played_at >= cutoff_100d }
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
          a.faction_id == lp.faction_id && a.match.played_at && a.match.played_at >= cutoff_1y
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
end
