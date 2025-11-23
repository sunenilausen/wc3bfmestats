class PlayersController < ApplicationController
  before_action :set_player, only: %i[ show edit update destroy ]

  # GET /players or /players.json
  def index
    @sort_column = %w[elo_rating matches_played].include?(params[:sort]) ? params[:sort] : "elo_rating"
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"

    @players = Player.all
    if params[:search].present?
      @players = @players.where("nickname LIKE :search OR battletag LIKE :search", search: "%#{params[:search]}%")
    end

    @player_count = @players.count

    if @sort_column == "matches_played"
      @players = @players.left_joins(:matches).group("players.id").order(Arel.sql("COUNT(matches.id) #{@sort_direction}"))
    else
      @players = @players.includes(:matches).order(@sort_column => @sort_direction)
    end
  end

  # GET /players/1 or /players/1.json
  def show
  end

  # GET /players/new
  def new
    @player = Player.new
  end

  # GET /players/1/edit
  def edit
  end

  # POST /players or /players.json
  def create
    @player = Player.new(player_params)

    respond_to do |format|
      if @player.save
        format.html { redirect_to @player, notice: "Player was successfully created." }
        format.json { render :show, status: :created, location: @player }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @player.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /players/1 or /players/1.json
  def update
    respond_to do |format|
      if @player.update(player_params)
        format.html { redirect_to @player, notice: "Player was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @player }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @player.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /players/1 or /players/1.json
  def destroy
    @player.destroy!

    respond_to do |format|
      format.html { redirect_to players_path, notice: "Player was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_player
      @player = Player.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def player_params
      params.expect(player: [ :battletag, :nickname, :battlenet_name, :elo_rating, :region, :battlenet_number ])
    end
end
