class FactionsController < ApplicationController
  before_action :set_faction, only: %i[ show edit update destroy ]

  # GET /factions or /factions.json
  def index
    @factions = Faction.all
  end

  # GET /factions/1 or /factions/1.json
  def show
    players_with_stats = Player.joins(:appearances)
      .where(appearances: { faction_id: @faction.id })
      .group("players.id")
      .having("COUNT(appearances.id) >= 10")
      .select("players.*, COUNT(appearances.id) as games_count")

    @top_winrate_players = players_with_stats.map do |player|
      wins = player.wins_with_faction(@faction)
      games = player.appearances.where(faction: @faction).count
      winrate = games > 0 ? (wins.to_f / games * 100).round(1) : 0
      { player: player, wins: wins, games: games, winrate: winrate }
    end.sort_by { |p| -p[:winrate] }.first(10)

    @most_wins_players = Player.joins(:appearances)
      .where(appearances: { faction_id: @faction.id })
      .group("players.id")
      .select("players.*")
      .map do |player|
        wins = player.wins_with_faction(@faction)
        games = player.appearances.where(faction: @faction).count
        { player: player, wins: wins, games: games }
      end.sort_by { |p| -p[:wins] }.first(10)

    # Calculate average kills stats for this faction
    faction_appearances = @faction.appearances
    @avg_unit_kills = faction_appearances.average(:unit_kills) || 0
    @avg_hero_kills = faction_appearances.average(:hero_kills) || 0

    # Calculate per-minute stats
    appearances_with_duration = faction_appearances.joins(:match).where.not(matches: { seconds: nil })
    if appearances_with_duration.any?
      total_unit_kills = appearances_with_duration.sum(:unit_kills) || 0
      total_hero_kills = appearances_with_duration.sum(:hero_kills) || 0
      total_minutes = appearances_with_duration.joins(:match).sum("matches.seconds") / 60.0
      @avg_unit_kills_per_min = total_minutes > 0 ? total_unit_kills / total_minutes : 0
      @avg_hero_kills_per_min = total_minutes > 0 ? total_hero_kills / total_minutes : 0
    else
      @avg_unit_kills_per_min = 0
      @avg_hero_kills_per_min = 0
    end
  end

  # GET /factions/new
  def new
    @faction = Faction.new
  end

  # GET /factions/1/edit
  def edit
  end

  # POST /factions or /factions.json
  def create
    @faction = Faction.new(faction_params)

    respond_to do |format|
      if @faction.save
        format.html { redirect_to @faction, notice: "Faction was successfully created." }
        format.json { render :show, status: :created, location: @faction }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @faction.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /factions/1 or /factions/1.json
  def update
    respond_to do |format|
      if @faction.update(faction_params)
        format.html { redirect_to @faction, notice: "Faction was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @faction }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @faction.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /factions/1 or /factions/1.json
  def destroy
    @faction.destroy!

    respond_to do |format|
      format.html { redirect_to factions_path, notice: "Faction was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_faction
      @faction = Faction.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def faction_params
      params.expect(faction: [ :name, :good, :color ])
    end
end
