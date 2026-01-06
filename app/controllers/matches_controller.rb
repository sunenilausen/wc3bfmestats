class MatchesController < ApplicationController
  load_and_authorize_resource except: %i[index show new create sync edit update destroy refetch toggle_reviewed]
  before_action :set_match, only: %i[show edit update destroy toggle_reviewed]
  authorize_resource only: %i[new create show edit update destroy toggle_reviewed]
  before_action :authorize_admin!, only: [ :sync ]

  # GET /matches or /matches.json
  def index
    @per_page = 50
    @page = [ params[:page].to_i, 1 ].max
    is_admin = current_user&.admin?

    # Cache total count (separate for admin vs non-admin)
    count_cache_key = [ "matches_count", is_admin, StatsCacheKey.key ]
    @total_count = Rails.cache.fetch(count_cache_key) do
      is_admin ? Match.count : Match.where(ignored: false).count
    end
    @total_pages = (@total_count.to_f / @per_page).ceil

    # Only show ignored matches to admins
    base_scope = is_admin ? Match : Match.where(ignored: false)

    # Use select to only load needed columns, preload associations separately
    @matches = base_scope.includes(appearances: [ :player, :faction ])

    case params[:sort]
    when "duration"
      direction = params[:direction] == "asc" ? "ASC" : "DESC"
      @matches = @matches.order(Arel.sql("COALESCE(seconds, 0) #{direction}"))
    when "date"
      @matches = params[:direction] == "desc" ? @matches.reverse_chronological : @matches.chronological
    else
      # Default to reverse chronological order (newest first)
      @matches = @matches.reverse_chronological
    end

    @matches = @matches.limit(@per_page).offset((@page - 1) * @per_page)
  end

  # GET /matches/1 or /matches/1.json
  def show
    # Hide ignored matches from non-admins
    if @match.ignored? && !current_user&.admin?
      redirect_to matches_path, alert: "Match not found."
      return
    end

    # Get all matches in chronological order and find previous/next
    ordered_ids = Match.chronological.pluck(:id)
    current_index = ordered_ids.index(@match.id)

    if current_index
      @previous_match = current_index > 0 ? Match.includes(:wc3stats_replay).find(ordered_ids[current_index - 1]) : nil
      @next_match = current_index < ordered_ids.length - 1 ? Match.includes(:wc3stats_replay).find(ordered_ids[current_index + 1]) : nil
    end

    # Preload rank data for prediction display
    preload_rank_data
  end

  # GET /matches/new
  def new
    @match = Match.new
    Faction.all.each { |faction| @match.appearances.build(faction: faction) }
  end

  # GET /matches/1/edit
  def edit
    # Build missing appearances for matches without full player data (e.g., ignored matches)
    if @match.appearances.empty? && @match.wc3stats_replay.present?
      build_appearances_from_replay
    elsif @match.appearances.empty?
      Faction.order(:id).each do |faction|
        @match.appearances.build(faction: faction)
      end
    end
  end

  # POST /matches or /matches.json
  def create
    @match = Match.new(match_params)

    @match.seconds = ChronicDuration.parse(params[:match][:seconds]) if params[:match][:seconds].present?

    params[:match][:appearances_attributes].each_value do |appearance_attrs|
      @match.appearances.build(appearance_attrs.permit(:id, :hero_kills, :player_id, :unit_kills, :faction_id))
    end

    respond_to do |format|
      if @match.save
        # Recalculate ratings in background (cancels any pending recalculations)
        RatingRecalculationJob.enqueue_and_cancel_pending

        # Retrain prediction model if enough new matches
        PredictionWeight.retrain_if_needed!

        format.html { redirect_to @match, notice: "Match was successfully created. Ratings are being recalculated." }
        format.json { render :show, status: :created, location: @match }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @match.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /matches/1 or /matches/1.json
  def update
    @match.assign_attributes(match_params)
    @match.seconds = ChronicDuration.parse(params[:match][:seconds]) if params[:match][:seconds].present?

    params[:match][:appearances_attributes].each_value do |appearance_attrs|
      permitted = appearance_attrs.permit(:id, :hero_kills, :player_id, :unit_kills, :faction_id)

      if permitted[:id].present?
        # Update existing appearance
        appearance = @match.appearances.find { |a| a.id == permitted[:id].to_i }
        appearance&.assign_attributes(permitted.except(:id))
      elsif permitted[:faction_id].present?
        # Create new appearance
        @match.appearances.build(permitted.except(:id))
      end
    end

    respond_to do |format|
      if @match.save
        RatingRecalculationJob.enqueue_and_cancel_pending

        format.html { redirect_to @match, notice: "Match was successfully updated. Ratings are being recalculated.", status: :see_other }
        format.json { render :show, status: :ok, location: @match }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @match.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /matches/1 or /matches/1.json
  def destroy
    @match.destroy!

    respond_to do |format|
      format.html { redirect_to matches_path, notice: "Match was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  # POST /matches/sync
  def sync
    limit = params[:limit].to_i
    limit = 1 if limit < 1
    limit = 100 if limit > 100
    Wc3statsSyncJob.perform_later("recent", limit)
    redirect_to matches_path, notice: "Sync job started for #{limit} replays. New matches will appear shortly."
  end

  # POST /matches/:id/refetch
  def refetch
    @match = Match.find_by_checksum_or_id(params[:id])
    raise ActiveRecord::RecordNotFound, "Match not found" unless @match

    unless current_user&.admin?
      redirect_to @match, alert: "You are not authorized to perform this action."
      return
    end

    replay = @match.wc3stats_replay
    unless replay
      redirect_to @match, alert: "Cannot refetch: no replay data associated with this match."
      return
    end

    replay_id = replay.wc3stats_replay_id
    Rails.logger.info "Refetch: Starting refetch for replay #{replay_id}"

    # Delete match and replay
    @match.destroy
    replay.destroy
    Rails.logger.info "Refetch: Deleted old match and replay"

    # Refetch from wc3stats
    replay_fetcher = Wc3stats::ReplayFetcher.new(replay_id)
    new_replay = replay_fetcher.call

    if new_replay
      new_match = new_replay.match
      if new_match
        Rails.logger.info "Refetch: Successfully rebuilt match #{new_match.id}"
        # Recalculate ratings
        RatingRecalculationJob.enqueue_and_cancel_pending
        redirect_to new_match, notice: "Match refetched successfully (replay ##{replay_id}). Ratings are being recalculated."
      else
        Rails.logger.error "Refetch: Replay saved but no match created"
        redirect_to matches_path, alert: "Failed to rebuild match from refetched replay."
      end
    else
      Rails.logger.error "Refetch: Failed to fetch replay: #{replay_fetcher.errors.join(', ')}"
      redirect_to matches_path, alert: "Failed to refetch replay: #{replay_fetcher.errors.first}"
    end
  end

  def toggle_reviewed
    @match.update!(reviewed: !@match.reviewed)
    redirect_to @match, notice: @match.reviewed? ? "Match marked as reviewed." : "Match unmarked as reviewed."
  end

  private

  def authorize_admin!
    unless current_user&.admin?
      redirect_to matches_path, alert: "You are not authorized to perform this action."
    end
  end

  def build_appearances_from_replay
    replay = @match.wc3stats_replay
    slot_to_faction = Wc3stats::MatchBuilder::SLOT_TO_FACTION

    # Build appearances for each faction, pre-filling player from replay data
    Faction.order(:id).each do |faction|
      # Find the slot for this faction
      slot = slot_to_faction.key(faction.name)
      player_data = replay.players.find { |p| p["slot"] == slot } if slot

      # Find or create the player
      player = nil
      if player_data
        battletag = player_data["name"]
        # Try both raw and encoding-fixed versions (for Korean/Unicode names)
        player = Player.find_by(battletag: battletag) ||
                 Player.find_by(battletag: replay.fix_encoding(battletag))
      end

      @match.appearances.build(
        faction: faction,
        player: player,
        unit_kills: player_data&.dig("variables", "unitKills"),
        hero_kills: player_data&.dig("variables", "heroKills")
      )
    end
  end

  def set_match
    @match = Match.find_by_checksum_or_id(params[:id])
    raise ActiveRecord::RecordNotFound, "Match not found" unless @match
  end

    # Only allow a list of trusted parameters through.
    def match_params
      params.expect(match: [ :uploaded_at, :seconds, :good_victory, :is_draw, :has_early_leaver, :ignored, appearances_attributes: [ :id, :hero_kills, :player_id, :unit_kills ] ])
    end

    def preload_rank_data
      player_ids = @match.appearances.map(&:player_id).compact
      return if player_ids.empty?

      # Get overall average ranks for each player
      @overall_avg_ranks = Appearance.joins(:match)
        .where(player_id: player_ids, matches: { ignored: false })
        .where.not(contribution_rank: nil)
        .group(:player_id)
        .average(:contribution_rank)
        .transform_values(&:to_f)

      # Get faction-specific avg ranks and counts
      faction_data = Appearance.joins(:match)
        .where(player_id: player_ids, matches: { ignored: false })
        .where.not(contribution_rank: nil)
        .group(:player_id, :faction_id)
        .pluck(:player_id, :faction_id, Arel.sql("AVG(contribution_rank)"), Arel.sql("COUNT(*)"))

      @faction_rank_data = {}
      faction_data.each do |player_id, faction_id, avg_rank, count|
        @faction_rank_data[[ player_id, faction_id ]] = { avg: avg_rank.to_f, count: count }
      end
    end
end
