class MatchesController < ApplicationController
  before_action :set_match, only: %i[ show edit update destroy ]

  # GET /matches or /matches.json
  def index
    @matches = Match.includes(appearances: [:player, :faction]).all
  end

  # GET /matches/1 or /matches/1.json
  def show
    @previous_match = Match.where("COALESCE(played_at, created_at) < ?", @match.played_at || @match.created_at)
                           .order(Arel.sql("COALESCE(played_at, created_at) DESC")).first
    @next_match = Match.where("COALESCE(played_at, created_at) > ?", @match.played_at || @match.created_at)
                       .order(Arel.sql("COALESCE(played_at, created_at) ASC")).first
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

    update_match

    respond_to do |format|
      if @match.save
        calculate_and_update_elo_ratings(@match)
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
    # Store old ELO changes before recalculating
    revert_elo_ratings(@match)

    @match.assign_attributes(match_params)
    @match.seconds = ChronicDuration.parse(params[:match][:seconds]) if params[:match][:seconds].present?

    params[:match][:appearances_attributes].each_value do |appearance_attrs|
      appearance = @match.appearances.find { |a| a.id == appearance_attrs[:id].to_i }
      if appearance
        appearance.assign_attributes(appearance_attrs.permit(:hero_kills, :player_id, :unit_kills, :faction_id))
      end
    end

    update_match

    respond_to do |format|
      if @match.save
        calculate_and_update_elo_ratings(@match)
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
      params.expect(match: [ :played_at, :seconds, :good_victory, :ignored, appearances_attributes: [ :id, :hero_kills, :player_id, :unit_kills ] ])
    end

    def update_match
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
    end

    def calculate_and_update_elo_ratings(match)
      k_factor = 32

      rating_changes = match.appearances.map do |appearance|
        player = appearance.player
        next unless player&.elo_rating

        opponent_avg = opponent_average_elo(match, appearance)
        next if opponent_avg.nil?

        expected_score = 1.0 / (1.0 + 10 ** ((opponent_avg - player.elo_rating) / 400.0))
        actual_score = match.good_victory == appearance.faction.good ? 1 : 0

        elo_change = (k_factor * (actual_score - expected_score)).round
        appearance.elo_rating_change = elo_change
        appearance.elo_rating = player.elo_rating
        elo_change
      end

      match.appearances.each_with_index do |appearance, index|
        next unless appearance.player && rating_changes[index]
        new_elo = appearance.player.elo_rating + rating_changes[index]
        appearance.player.update(elo_rating: new_elo)
        appearance.save
      end
    end

    def opponent_average_elo(match, appearance)
      opponent_appearances = match.appearances.reject { |a| a.faction.good == appearance.faction.good }
      return nil if opponent_appearances.empty?

      total_elo = opponent_appearances.sum { |a| a.player&.elo_rating.to_i }
      (total_elo.to_f / opponent_appearances.size)
    end

    def revert_elo_ratings(match)
      match.appearances.each do |appearance|
        next unless appearance.player && appearance.elo_rating_change

        reverted_elo = appearance.player.elo_rating - appearance.elo_rating_change
        appearance.player.update(elo_rating: reverted_elo)
        appearance.elo_rating_change = nil
        appearance.elo_rating = nil
        appearance.save
      end
    end

    def opponent_average_elo_for_update(match, appearance)
      opponent_appearances = match.appearances.reject { |a| a.faction.good == appearance.faction.good }
      return nil if opponent_appearances.empty?

      total_elo = opponent_appearances.sum do |a|
        # Use historical rating for opponents too
        (a.elo_rating || a.player&.elo_rating).to_i
      end
      (total_elo.to_f / opponent_appearances.size)
    end
end
