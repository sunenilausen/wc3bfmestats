class LobbiesController < ApplicationController
  before_action :set_lobby, only: %i[ show edit update destroy ]

  # GET /lobbies or /lobbies.json
  def index
    @lobbies = Lobby.all
  end

  # GET /lobbies/1 or /lobbies/1.json
  def show
  end

  # GET /lobbies/new
  def new
    @lobby = Lobby.new
    latest_match = Match.order(played_at: :desc).first

    Faction.all.each do |faction|
      # Find player from latest match who played this faction
      player_id = latest_match&.appearances&.find_by(faction: faction)&.player_id
      @lobby.lobby_players.build(faction: faction, player_id: player_id)
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

    respond_to do |format|
      format.html { redirect_to @lobby, notice: "Lobby was successfully updated.", status: :see_other }
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
end
