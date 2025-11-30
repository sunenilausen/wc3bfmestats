class MatchesController < ApplicationController
  load_and_authorize_resource except: %i[index show new create sync edit update destroy]
  before_action :set_match, only: %i[show edit update destroy]
  authorize_resource only: %i[new create show edit update destroy]
  before_action :authorize_admin!, only: [ :sync ]

  # GET /matches or /matches.json
  def index
    @per_page = 50
    @page = [ params[:page].to_i, 1 ].max
    @total_count = Match.count
    @total_pages = (@total_count.to_f / @per_page).ceil

    @matches = Match.includes(appearances: [ :player, :faction ])

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
    # Get all matches in chronological order and find previous/next
    ordered_ids = Match.chronological.pluck(:id)
    current_index = ordered_ids.index(@match.id)

    if current_index
      @previous_match = current_index > 0 ? Match.includes(:wc3stats_replay).find(ordered_ids[current_index - 1]) : nil
      @next_match = current_index < ordered_ids.length - 1 ? Match.includes(:wc3stats_replay).find(ordered_ids[current_index + 1]) : nil
    end
  end

  # GET /matches/new
  def new
    @match = Match.new
    Faction.all.each { |faction| @match.appearances.build(faction: faction) }
  end

  # GET /matches/1/edit
  def edit
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
        # Recalculate ratings when match is created
        CustomRatingRecalculator.new.call

        # Retrain prediction model if enough new matches
        PredictionWeight.retrain_if_needed!

        format.html { redirect_to @match, notice: "Match was successfully created." }
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
      appearance = @match.appearances.find { |a| a.id == appearance_attrs[:id].to_i }
      if appearance
        appearance.assign_attributes(appearance_attrs.permit(:hero_kills, :player_id, :unit_kills, :faction_id))
      end
    end

    respond_to do |format|
      if @match.save
        # Recalculate ratings when match is updated
        CustomRatingRecalculator.new.call

        format.html { redirect_to @match, notice: "Match was successfully updated.", status: :see_other }
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

  private

  def authorize_admin!
    unless current_user&.admin?
      redirect_to matches_path, alert: "You are not authorized to perform this action."
    end
  end

  def set_match
    @match = Match.find_by_checksum_or_id(params[:id])
    raise ActiveRecord::RecordNotFound, "Match not found" unless @match
  end

    # Only allow a list of trusted parameters through.
    def match_params
      params.expect(match: [ :uploaded_at, :seconds, :good_victory, :ignored, appearances_attributes: [ :id, :hero_kills, :player_id, :unit_kills ] ])
    end
end
