class PlayersController < ApplicationController
  load_and_authorize_resource except: %i[index]

  # GET /players or /players.json
  def index
    @sort_column = %w[custom_rating matches_played matches_observed ml_score].include?(params[:sort]) ? params[:sort] : "ml_score"
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"

    @players = Player.all
    if params[:search].present?
      @players = @players.where("nickname LIKE :search OR battletag LIKE :search", search: "%#{params[:search]}%")
    end

    # Filter by minimum games played
    @min_games = params[:min_games].to_i
    if @min_games > 0
      player_ids_with_min_games = Appearance.joins(:match)
                                            .where(matches: { ignored: false })
                                            .group(:player_id)
                                            .having("COUNT(DISTINCT match_id) >= ?", @min_games)
                                            .pluck(:player_id)
      @players = @players.where(id: player_ids_with_min_games)
    end

    # Filter out inactive players (no games in last 2 years) by default
    @show_inactive = params[:show_inactive] == "1"
    unless @show_inactive
      two_years_ago = 2.years.ago
      active_player_ids = Match.where(ignored: false)
                               .where("uploaded_at >= ?", two_years_ago)
                               .joins(:appearances)
                               .select("appearances.player_id")
                               .distinct
                               .pluck(:player_id)
      @players = @players.where(id: active_player_ids)
    end

    # Count players with valid (non-ignored) matches
    @player_count = @players.joins(:matches).merge(Match.where(ignored: false)).distinct.count
    # Count players who have never played a valid match (only observed or only played ignored matches)
    players_with_valid_matches = Player.joins(:matches).merge(Match.where(ignored: false)).distinct.pluck(:id)
    @observer_count = @players.where.not(id: players_with_valid_matches).count

    # Precompute observation counts for all players (only from non-ignored matches)
    @observation_counts = Hash.new(0)
    Wc3statsReplay.joins(:match).where(matches: { ignored: false }).find_each do |replay|
      replay.players.each do |p|
        if p["slot"].nil? || p["slot"] > 9 || p["isWinner"].nil?
          @observation_counts[p["name"]] += 1
        end
      end
    end

    if @sort_column == "matches_played"
      @players = @players.left_joins(:matches).where(matches: { ignored: false }).or(@players.left_joins(:matches).where(matches: { id: nil })).group("players.id").order(Arel.sql("COUNT(matches.id) #{@sort_direction}"))
    elsif @sort_column == "matches_observed"
      @players = @players.includes(:matches).sort_by { |p| @observation_counts[p.battletag] }
      @players = @players.reverse if @sort_direction == "desc"
    elsif @sort_column == "ml_score"
      @players = @players.includes(:matches).order(ml_score: @sort_direction)
    else
      @players = @players.includes(:matches).order(@sort_column => @sort_direction)
    end
  end

  # GET /players/1 or /players/1.json
  def show
    cache_key = ["player_stats", @player.id, StatsCacheKey.key]

    # Preload all data needed for stats computation (exclude ignored matches)
    # Order by reverse chronological (newest first) using same ordering as matches index
    @appearances = @player.appearances
      .joins(:match)
      .where(matches: { ignored: false })
      .includes(:faction, :match, match: { appearances: :faction, wc3stats_replay: {} })
      .merge(Match.reverse_chronological)

    # Compute all stats in a single pass (cached)
    @stats = Rails.cache.fetch(cache_key + ["basic"]) do
      stats = PlayerStatsCalculator.new(@player, @appearances).compute
      # Convert Hash with default proc to regular Hash for caching
      stats[:faction_stats] = Hash[stats[:faction_stats]] if stats[:faction_stats]
      stats
    end

    # Compute hero and base death stats from replay events (cached)
    @event_stats = Rails.cache.fetch(cache_key + ["events"]) do
      PlayerEventStatsCalculator.new(@player).compute
    end

    # Compute ranks (cached separately since they change with other players)
    @ranks = Rails.cache.fetch(cache_key + ["ranks"]) do
      {
        cr_rank: @player.cr_rank,
        ml_rank: @player.ml_rank,
        cr_total: Player.ranked_player_count_by_cr,
        ml_total: Player.ranked_player_count_by_ml
      }
    end
  end

  # GET /players/new
  def new
  end

  # GET /players/1/edit
  def edit
  end

  # POST /players or /players.json
  def create
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

    # Only allow a list of trusted parameters through.
    def player_params
      params.expect(player: [ :battletag, :nickname, :battlenet_name, :region, :battlenet_number ])
    end
end
