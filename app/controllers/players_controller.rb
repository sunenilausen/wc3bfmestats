class PlayersController < ApplicationController
  before_action :set_player, only: %i[ show edit update destroy ]

  # GET /players or /players.json
  def index
    @sort_column = %w[elo_rating glicko2_rating matches_played matches_observed].include?(params[:sort]) ? params[:sort] : "elo_rating"
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"

    @players = Player.all
    if params[:search].present?
      @players = @players.where("nickname LIKE :search OR battletag LIKE :search", search: "%#{params[:search]}%")
    end

    # Filter by minimum games played
    @min_games = params[:min_games].to_i
    if @min_games > 0
      player_ids_with_min_games = Appearance.group(:player_id)
                                            .having("COUNT(DISTINCT match_id) >= ?", @min_games)
                                            .pluck(:player_id)
      @players = @players.where(id: player_ids_with_min_games)
    end

    @player_count = @players.joins(:matches).distinct.count
    @observer_count = @players.left_joins(:matches).where(matches: { id: nil }).count

    # Precompute observation counts for all players
    @observation_counts = Hash.new(0)
    Wc3statsReplay.find_each do |replay|
      replay.players.each do |p|
        if p["slot"].nil? || p["slot"] > 9 || p["isWinner"].nil?
          @observation_counts[p["name"]] += 1
        end
      end
    end

    if @sort_column == "matches_played"
      @players = @players.left_joins(:matches).group("players.id").order(Arel.sql("COUNT(matches.id) #{@sort_direction}"))
    elsif @sort_column == "matches_observed"
      @players = @players.includes(:matches).sort_by { |p| @observation_counts[p.battletag] }
      @players = @players.reverse if @sort_direction == "desc"
    else
      @players = @players.includes(:matches).order(@sort_column => @sort_direction)
    end
  end

  # GET /players/1 or /players/1.json
  def show
    # Preload all data needed for stats computation
    @appearances = @player.appearances
      .includes(:faction, match: { appearances: :faction })
      .order("matches.played_at DESC, matches.created_at DESC")

    # Compute all stats in a single pass
    @stats = PlayerStatsCalculator.new(@player, @appearances).compute
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
