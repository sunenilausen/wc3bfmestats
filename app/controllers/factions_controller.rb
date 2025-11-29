class FactionsController < ApplicationController
  load_and_authorize_resource except: %i[index]

  # GET /factions or /factions.json
  def index
    @factions = Faction.all
  end

  # GET /factions/1 or /factions/1.json
  def show
    @stats = FactionStatsCalculator.new(@faction).compute
    event_stats = FactionEventStatsCalculator.new(@faction).compute
    @hero_stats = event_stats[:hero_stats]
    @hero_loss_stats = event_stats[:hero_loss_stats]
    @base_stats = event_stats[:base_stats]
    @base_loss_stats = event_stats[:base_loss_stats]
    @ring_event_stats = event_stats[:ring_event_stats]
    @hero_uptime = event_stats[:hero_uptime]
    @base_uptime = event_stats[:base_uptime]
    @hero_kills = event_stats[:hero_kills]
    @hero_deaths = event_stats[:hero_deaths]
    @hero_kd_ratio = event_stats[:hero_kd_ratio]
  end

  # GET /factions/1/edit
  def edit
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

  private

    # Only allow a list of trusted parameters through.
    def faction_params
      params.expect(faction: [ :name, :good, :color ])
    end
end
