class MatchesController < ApplicationController
  load_and_authorize_resource except: %i[index new create]
  authorize_resource only: %i[new create]

  # GET /matches or /matches.json
  def index
    @matches = Match.includes(appearances: [ :player, :faction ])

    case params[:sort]
    when "duration"
      direction = params[:direction] == "asc" ? "ASC" : "DESC"
      @matches = @matches.order(Arel.sql("COALESCE(seconds, 0) #{direction}"))
    when "date"
      direction = params[:direction] == "asc" ? "ASC" : "DESC"
      @matches = @matches.order(Arel.sql("COALESCE(played_at, created_at) #{direction}"))
    else
      @matches = @matches.order(played_at: :desc)
    end
  end

  # GET /matches/1 or /matches/1.json
  def show
    # Get all matches in chronological order and find previous/next
    ordered_ids = Match.chronological.pluck(:id)
    current_index = ordered_ids.index(@match.id)

    if current_index
      @previous_match = current_index > 0 ? Match.find(ordered_ids[current_index - 1]) : nil
      @next_match = current_index < ordered_ids.length - 1 ? Match.find(ordered_ids[current_index + 1]) : nil
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
        EloRecalculator.new.call
        Glicko2Recalculator.new.call

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

  private

    # Only allow a list of trusted parameters through.
    def match_params
      params.expect(match: [ :played_at, :seconds, :good_victory, :ignored, appearances_attributes: [ :id, :hero_kills, :player_id, :unit_kills ] ])
    end
end
