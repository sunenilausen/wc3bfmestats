class MatchesController < ApplicationController
  before_action :set_match, only: %i[ show edit update destroy ]

  # GET /matches or /matches.json
  def index
    @matches = Match.all
  end

  # GET /matches/1 or /matches/1.json
  def show
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

    if params[:quickimport_json].present?
      # Handle quick import JSON here
      # Expected format:
      # [
      #   { "Player": "Snaps", "Hero Kills": 2, "Unit Kills": 83 },
      #   ...
      # ]
      begin
        appearances_data = JSON.parse(params[:quickimport_json])
        appearances_data.each_with_index do |data, i|
          player_nickname = data["Player"]
          hero_kills = data["Hero Kills"]
          unit_kills = data["Unit Kills"]

          unless player_nickname.nil? || player_nickname.strip.empty?
            player_nickname = player_nickname.split("#").first.strip unless player_nickname.split("#").first.strip.empty?
            player = Player.find_by(nickname: player_nickname)
            player ||= Player.create(nickname: player_nickname, elo_rating: 1500)
          end

          @match.appearances[i].tap do |appearance|
            appearance.player = player unless player.nil?
            appearance.hero_kills = hero_kills
            appearance.unit_kills = unit_kills
          end
        end
      rescue JSON::ParserError => e
        # Handle JSON parsing error (e.g., log it, notify user) if needed
      end
    end

    calculate_and_update_elo_ratings(@match)

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
    respond_to do |format|
      if @match.update(match_params)
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
    # Use callbacks to share common setup or constraints between actions.
    def set_match
      @match = Match.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def match_params
      params.expect(match: [ :played_at, :seconds, :good_victory, appearances_attributes: [ :id, :hero_kills, :player_id, :unit_kills ] ])
    end

    def calculate_and_update_elo_ratings(match)
      k_factor = 32

      rating_changes = match.appearances.map do |appearance|
        player = appearance.player
        next unless player.elo_rating

        expected_score = 1.0 / (1.0 + 10 ** ((opponent_average_elo(match, appearance) - player.elo_rating) / 400.0))
        actual_score = match.good_victory == appearance.faction.good ? 1 : 0

        elo_change = (k_factor * (actual_score - expected_score)).round
        appearance.elo_rating_change = elo_change
        appearance.elo_rating = player.elo_rating
        elo_change
      end

      match.appearances.each_with_index do |appearance, index|
        new_elo = appearance.player.elo_rating + rating_changes[index]
        appearance.player.update(elo_rating: new_elo)
      end
    end

    def opponent_average_elo(match, appearance)
      opponent_appearances = match.appearances.reject { |a| a.faction.good == appearance.faction.good }
      total_elo = opponent_appearances.sum { |a| a.player.elo_rating.to_i }
      (total_elo.to_f / opponent_appearances.size)
    end
end
