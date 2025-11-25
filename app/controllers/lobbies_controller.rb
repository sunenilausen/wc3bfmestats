class LobbiesController < ApplicationController
  before_action :set_lobby, only: %i[ show edit update destroy ]

  # GET /lobbies or /lobbies.json
  def index
    @lobbies = Lobby.all
  end

  # GET /lobbies/1 or /lobbies/1.json
  def show
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
      @lobby = Lobby.find(params.expect(:id))
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
    end
end
