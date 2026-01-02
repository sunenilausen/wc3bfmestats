class PlayersController < ApplicationController
  load_and_authorize_resource except: %i[index show edit update destroy]
  before_action :set_player, only: %i[show edit update destroy]
  authorize_resource only: %i[show edit update destroy]

  # GET /players or /players.json
  def index
    @sort_column = %w[custom_rating matches_played matches_observed ml_score].include?(params[:sort]) ? params[:sort] : "custom_rating"
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"

    @players = Player.all
    if params[:search].present?
      @players = @players.where(
        "LOWER(nickname) LIKE :search OR LOWER(battletag) LIKE :search OR LOWER(alternative_name) LIKE :search",
        search: "%#{params[:search].downcase}%"
      )
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

    # Precompute CR ranks for all players (global ranks, not affected by filters)
    @cr_ranks = {}
    Player.joins(:matches)
      .where(matches: { ignored: false })
      .where.not(players: { custom_rating: nil })
      .distinct
      .order(custom_rating: :desc)
      .pluck(:id)
      .each_with_index { |id, idx| @cr_ranks[id] = idx + 1 }

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
    @version_filter = params[:version_filter]
    @available_map_versions = Rails.cache.fetch([ "available_map_versions", StatsCacheKey.key ]) do
      Match.where(ignored: false)
        .where.not(map_version: nil)
        .distinct
        .pluck(:map_version)
        .sort_by do |v|
          match = v.match(/^(\d+)\.(\d+)([a-zA-Z]*)/)
          if match
            [ match[1].to_i, match[2].to_i, match[3].to_s ]
          else
            [ 0, 0, v ]
          end
        end
        .reverse
    end

    # Parse version filter (format: "from:4.5e", "only:4.5e", or "last:100")
    @map_version = nil
    @map_version_until = nil
    @last_n_games = nil
    if @version_filter.present?
      if @version_filter.start_with?("only:")
        @map_version = @version_filter.sub("only:", "")
      elsif @version_filter.start_with?("from:")
        @map_version_until = @version_filter.sub("from:", "")
      elsif @version_filter.start_with?("last:")
        @last_n_games = @version_filter.sub("last:", "").to_i
      end
    end

    # Determine which map versions to include based on filter
    @filtered_map_versions = if @map_version.present?
      [ @map_version ]
    elsif @map_version_until.present?
      until_index = @available_map_versions.index(@map_version_until)
      if until_index
        @available_map_versions[0..until_index]
      else
        @available_map_versions
      end
    else
      @available_map_versions
    end

    # Preload all data needed for stats computation (exclude ignored and early leaver matches)
    # Order by reverse chronological (newest first) using same ordering as matches index
    base_scope = @player.appearances
      .joins(:match)
      .where(matches: { ignored: false, has_early_leaver: false })
      .includes(:faction, :match, match: { appearances: :faction, wc3stats_replay: {} })
      .merge(Match.reverse_chronological)

    # Filter by map versions if specified
    if @map_version.present? || @map_version_until.present?
      base_scope = base_scope.where(matches: { map_version: @filtered_map_versions })
    end

    # Filter by last N games if specified
    if @last_n_games.present? && @last_n_games > 0
      base_scope = base_scope.limit(@last_n_games)
    end

    @appearances = base_scope

    cache_key = [ "player_stats", @player.id, @version_filter, StatsCacheKey.key ]

    # Compute all stats in a single pass (cached)
    @stats = Rails.cache.fetch(cache_key + [ "basic" ]) do
      stats = PlayerStatsCalculator.new(@player, @appearances).compute
      # Convert Hash with default proc to regular Hash for caching
      stats[:faction_stats] = Hash[stats[:faction_stats]] if stats[:faction_stats]
      stats
    end

    # Compute hero and base death stats from replay events (cached)
    @event_stats = Rails.cache.fetch(cache_key + [ "events" ]) do
      PlayerEventStatsCalculator.new(@player, map_versions: (@map_version.present? || @map_version_until.present?) ? @filtered_map_versions : nil).compute
    end

    # Compute ranks (cached separately since they change with other players)
    # Note: ranks are global, not filtered by map version
    @ranks = Rails.cache.fetch([ "player_stats", @player.id, StatsCacheKey.key, "ranks" ]) do
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

    def set_player
      @player = Player.find_by_battletag_or_id(params[:id])
      raise ActiveRecord::RecordNotFound, "Player not found" unless @player
    end

    # Only allow a list of trusted parameters through.
    def player_params
      params.expect(player: [
        :battletag, :nickname, :alternative_name, :region,
        :custom_rating_seed, :elo_rating_seed, :glicko2_rating_seed
      ])
    end
end
