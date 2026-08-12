class PlayersController < ApplicationController
  load_and_authorize_resource except: %i[index show details edit update destroy match_history]
  before_action :set_player, only: %i[show details edit update destroy]
  authorize_resource only: %i[show edit update destroy]

  # GET /players or /players.json
  def index
    @sort_column = %w[custom_rating matches_played matches_observed ml_score].include?(params[:sort]) ? params[:sort] : "custom_rating"
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"

    # Load all cached data upfront (globally cached, invalidated when stats change)
    cached_data = load_players_index_cache

    @players = Player.all
    if params[:search].present?
      @players = @players.where(
        "LOWER(nickname) LIKE :search OR LOWER(battletag) LIKE :search OR LOWER(alternative_name) LIKE :search",
        search: "%#{params[:search].downcase}%"
      )
    end

    # Filter by minimum games played (using cached counts)
    @min_games = params[:min_games].to_i
    if @min_games > 0
      player_ids_with_min_games = cached_data[:matches_played].select { |_id, count| count >= @min_games }.keys
      @players = @players.where(id: player_ids_with_min_games)
    end

    # Filter out inactive players (no games in last 2 years) by default
    @show_inactive = params[:show_inactive] == "1"
    unless @show_inactive
      @players = @players.where(id: cached_data[:active_player_ids])
    end

    # Use cached counts
    @matches_played = cached_data[:matches_played]
    @observation_counts = cached_data[:observation_counts]
    @cr_ranks = cached_data[:cr_ranks]

    # Count players with valid matches (from cached data)
    filtered_player_ids = @players.pluck(:id)
    @player_count = filtered_player_ids.count { |id| @matches_played[id].to_i > 0 }
    @observer_count = filtered_player_ids.count { |id| @matches_played[id].to_i == 0 }

    if @sort_column == "matches_played"
      @players = @players.sort_by { |p| @matches_played[p.id] || 0 }
      @players = @players.reverse if @sort_direction == "desc"
    elsif @sort_column == "matches_observed"
      @players = @players.sort_by { |p| @observation_counts[p.battletag] || 0 }
      @players = @players.reverse if @sort_direction == "desc"
    elsif @sort_column == "ml_score"
      @players = @players.order(ml_score: @sort_direction)
    else
      @players = @players.order(@sort_column => @sort_direction)
    end
  end

  # GET /players/1 or /players/1.json
  def show
    load_version_filter
    @appearances = build_stats_scope

    # Compute all stats in a single pass (cached)
    @stats = Rails.cache.fetch(player_stats_cache_key + [ "basic" ]) do
      stats = PlayerStatsCalculator.new(@player, @appearances).compute
      # Convert Hash with default proc to regular Hash for caching
      stats[:faction_stats] = Hash[stats[:faction_stats]] if stats[:faction_stats]
      stats
    end

    # Compute hero and base death stats from replay events (cached)
    # Use longer-lived cache since event stats rarely change
    @event_stats = Rails.cache.fetch(player_stats_cache_key + [ "events" ]) do
      PlayerEventStatsCalculator.new(@player, map_versions: (@map_version.present? || @map_version_until.present?) ? @filtered_map_versions : nil).compute
    end

    # Use prebuilt global rank caches (built by CachePrebuildJob)
    cr_ranks = Rails.cache.fetch([ "cr_ranks", StatsCacheKey.key ]) do
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

    ml_ranks = Rails.cache.fetch([ "ml_ranks", StatsCacheKey.key ]) do
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

    @ranks = {
      cr_rank: cr_ranks[@player.id],
      ml_rank: ml_ranks[@player.id],
      cr_total: cr_ranks.size,
      ml_total: ml_ranks.size
    }

    # Cache faction data (rarely changes)
    @good_factions = Rails.cache.fetch("good_factions", expires_in: 1.day) do
      Faction.where(good: true).order(:id).to_a
    end
    @evil_factions = Rails.cache.fetch("evil_factions", expires_in: 1.day) do
      Faction.where(good: false).order(:id).to_a
    end

    # Cache faction totals globally (for percentile calculations)
    @faction_totals = Rails.cache.fetch([ "faction_totals", StatsCacheKey.key ]) do
      PlayerFactionStat.where.not(faction_score: nil).group(:faction_id).count
    end

    # Preload player's faction stats
    @player_faction_stats = @player.player_faction_stats.includes(:faction).index_by(&:faction_id)

    # Compute avg enemy/team CR efficiently with a single query
    @avg_enemy_team_cr, @avg_team_cr = compute_team_cr_averages(@player, @appearances)
  end

  # GET /players/1/details - Advanced stats page (secondary stats)
  def details
    load_version_filter
    filtered_versions = (@map_version.present? || @map_version_until.present?) ? @filtered_map_versions : nil

    @hosting_stats = Rails.cache.fetch(player_stats_cache_key + [ "hosting", "v2" ]) do
      compute_hosting_stats(@player, map_versions: filtered_versions)
    end
  end

  def compute_team_cr_averages(player, appearances)
    return [ nil, nil ] if appearances.empty?

    match_ids = appearances.map { |a| a.match_id }.uniq
    return [ nil, nil ] if match_ids.empty?

    # Get all appearances for these matches in one query
    all_match_appearances = Appearance.where(match_id: match_ids)
      .includes(:faction)
      .where.not(custom_rating: nil)
      .pluck(:match_id, :player_id, :faction_id, :custom_rating)

    # Build lookup: match_id -> { good: [ratings], evil: [ratings] }
    match_ratings = Hash.new { |h, k| h[k] = { good: [], evil: [] } }
    faction_sides = Faction.pluck(:id, :good).to_h

    all_match_appearances.each do |match_id, pid, faction_id, cr|
      side = faction_sides[faction_id] ? :good : :evil
      match_ratings[match_id][side] << { player_id: pid, cr: cr }
    end

    # Build player's side lookup from their appearances
    player_sides = appearances.each_with_object({}) do |app, h|
      h[app.match_id] = app.faction&.good? ? :good : :evil
    end

    enemy_crs = []
    team_crs = []

    appearances.each do |app|
      player_side = player_sides[app.match_id]
      next unless player_side

      enemy_side = player_side == :good ? :evil : :good
      ratings = match_ratings[app.match_id]

      # Enemy team average
      enemy_ratings = ratings[enemy_side].map { |r| r[:cr] }
      enemy_crs << (enemy_ratings.sum / enemy_ratings.size.to_f) if enemy_ratings.any?

      # Team average (excluding self)
      team_ratings = ratings[player_side].reject { |r| r[:player_id] == player.id }.map { |r| r[:cr] }
      team_crs << (team_ratings.sum / team_ratings.size.to_f) if team_ratings.any?
    end

    avg_enemy = enemy_crs.any? ? (enemy_crs.sum / enemy_crs.size).round : nil
    avg_team = team_crs.any? ? (team_crs.sum / team_crs.size).round : nil

    [ avg_enemy, avg_team ]
  end

  # GET /players/1/match_history (lazy loaded via Turbo Frame)
  def match_history
    @player = Player.find_by_battletag_or_id(params[:id])
    raise ActiveRecord::RecordNotFound, "Player not found" unless @player

    @version_filter = params[:version_filter]

    # Build scope for match history (includes early leaver matches, unlike stats)
    base_scope = @player.appearances
      .joins(:match)
      .where(matches: { ignored: false })
      .includes(:faction, :match)
      .merge(Match.reverse_chronological)

    # Apply version filter
    if @version_filter.present?
      if @version_filter.start_with?("only:")
        base_scope = base_scope.where(matches: { map_version: @version_filter.sub("only:", "") })
      elsif @version_filter.start_with?("from:")
        map_version_until = @version_filter.sub("from:", "")
        available_versions = Match.where(ignored: false).where.not(map_version: nil).distinct.pluck(:map_version)
          .sort_by { |v| m = v.match(/^(\d+)\.(\d+)([a-zA-Z]*)/); m ? [ m[1].to_i, m[2].to_i, m[3].to_s ] : [ 0, 0, v ] }.reverse
        until_index = available_versions.index(map_version_until)
        filtered_versions = until_index ? available_versions[0..until_index] : available_versions
        base_scope = base_scope.where(matches: { map_version: filtered_versions })
      elsif @version_filter.start_with?("last:")
        base_scope = base_scope.limit(@version_filter.sub("last:", "").to_i)
      end
    end

    @appearances = base_scope
    render partial: "players/match_history", locals: { appearances: @appearances, player: @player }
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

    # Parses the version_filter param and sets filter instance variables
    def load_version_filter
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
    end

    # Preload appearances with includes needed for PlayerStatsCalculator
    # Note: match.appearances is needed for team/opponent stats
    # Order by reverse chronological (newest first) using same ordering as matches index
    # Stats exclude early leaver matches, but match history includes them
    def build_stats_scope
      stats_scope = @player.appearances
        .joins(:match)
        .where(matches: { ignored: false, has_early_leaver: false })
        .includes(:faction, match: { appearances: :faction })
        .merge(Match.reverse_chronological)

      # Filter by map versions if specified
      if @map_version.present? || @map_version_until.present?
        stats_scope = stats_scope.where(matches: { map_version: @filtered_map_versions })
      end

      # Filter by last N games if specified
      if @last_n_games.present? && @last_n_games > 0
        stats_scope = stats_scope.limit(@last_n_games)
      end

      stats_scope
    end

    # Use player-specific cache key for stats that only depend on this player's data
    # This avoids invalidating cache when OTHER players' matches change
    def player_stats_cache_key
      @player_stats_cache_key ||= begin
        player_last_match = @player.appearances.joins(:match).maximum("matches.updated_at")
        player_cache_version = player_last_match&.to_i || 0
        [ "player_stats", @player.id, @version_filter, player_cache_version ]
      end
    end

    # Stats about matches this player hosted (lobby host from replay data)
    def compute_hosting_stats(player, map_versions: nil)
      host_tags = [ player.battletag, *(player.alternative_battletags || []) ].compact

      hosted = Match.where(ignored: false, host_battletag: host_tags)
      hosted = hosted.where(map_version: map_versions) if map_versions
      total = hosted.count
      return nil if total == 0

      with_prediction = hosted.where.not(predicted_good_win_pct: nil)
      predicted = with_prediction.count
      balanced = with_prediction.merge(Match.balanced).count

      # Lobby balance brackets: how far from 50/50 the hosted games were,
      # in 5% steps of the favored team's predicted win chance (like /statistics)
      brackets = (50..95).step(5).map do |start|
        { label: "#{start}-#{start + 5}", count: 0 }
      end
      with_prediction.pluck(:predicted_good_win_pct).each do |pct|
        confidence = [ pct.to_f, 100 - pct.to_f ].max
        index = (((confidence - 50) / 5).floor).clamp(0, brackets.size - 1)
        brackets[index][:count] += 1
      end
      brackets.each do |bracket|
        bracket[:pct] = predicted > 0 ? (bracket[:count].to_f / predicted * 100).round(1) : 0
      end

      # Host's own record in the games they hosted AND played in,
      # split by predicted win chance of their team (same thresholds as player page:
      # underdog <45%, balanced 45-55%, favorite >55%)
      played_scope = player.appearances
        .joins(:match)
        .where(matches: { ignored: false, host_battletag: host_tags })
        .includes(:faction, :match)
      played_scope = played_scope.where(matches: { map_version: map_versions }) if map_versions

      record = { overall: [ 0, 0 ], favorite: [ 0, 0 ], balanced: [ 0, 0 ], underdog: [ 0, 0 ] }
      played = 0
      played_scope.each do |app|
        played += 1
        match = app.match
        next if match.is_draw?

        won = app.faction.good? == match.good_victory?
        record[:overall][won ? 0 : 1] += 1

        next if match.predicted_good_win_pct.nil?
        team_pct = app.faction.good? ? match.predicted_good_win_pct.to_f : 100 - match.predicted_good_win_pct.to_f
        role = team_pct < 45 ? :underdog : (team_pct > 55 ? :favorite : :balanced)
        record[role][won ? 0 : 1] += 1
      end

      wins, losses = record[:overall]

      {
        total: total,
        predicted: predicted,
        balanced: balanced,
        balanced_pct: predicted > 0 ? (balanced.to_f / predicted * 100).round(1) : nil,
        wins: wins,
        losses: losses,
        played: played,
        not_played: total - played,
        win_pct: (wins + losses) > 0 ? (wins.to_f / (wins + losses) * 100).round(1) : nil,
        record_by_role: record.except(:overall),
        brackets: brackets
      }
    end

    # Cache all expensive computations for players index
    def load_players_index_cache
      Rails.cache.fetch([ "players_index_data", StatsCacheKey.key ], expires_in: 1.hour) do
        compute_players_index_data
      end
    end

    def compute_players_index_data
      # Matches played per player (non-ignored matches only)
      matches_played = Appearance.joins(:match)
        .where(matches: { ignored: false })
        .group(:player_id)
        .count

      # Active player IDs (played in last 2 years)
      two_years_ago = 2.years.ago
      active_player_ids = Match.where(ignored: false)
        .where("uploaded_at >= ?", two_years_ago)
        .joins(:appearances)
        .select("appearances.player_id")
        .distinct
        .pluck(:player_id)

      # Observation counts (observers in replays)
      observation_counts = Hash.new(0)
      Wc3statsReplay.joins(:match).where(matches: { ignored: false }).find_each do |replay|
        replay.players.each do |p|
          if p["slot"].nil? || p["slot"] > 9 || p["isWinner"].nil?
            observation_counts[p["name"]] += 1
          end
        end
      end

      # CR ranks (global, sorted by custom_rating desc)
      cr_ranks = {}
      Player.joins(:matches)
        .where(matches: { ignored: false })
        .where.not(players: { custom_rating: nil })
        .distinct
        .order(custom_rating: :desc)
        .pluck(:id)
        .each_with_index { |id, idx| cr_ranks[id] = idx + 1 }

      {
        matches_played: matches_played,
        active_player_ids: active_player_ids,
        observation_counts: observation_counts,
        cr_ranks: cr_ranks
      }
    end

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
