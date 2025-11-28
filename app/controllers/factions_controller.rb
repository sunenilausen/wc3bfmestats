class FactionsController < ApplicationController
  load_and_authorize_resource except: %i[index]

  # GET /factions or /factions.json
  def index
    @factions = Faction.all
  end

  # GET /factions/1 or /factions/1.json
  def show
    @stats = FactionStatsCalculator.new(@faction).compute
    @hero_stats = HeroStatsCalculator.new(@faction).compute
    @base_stats = BaseStatsCalculator.new(@faction).compute
    @ring_event_stats = RingEventStatsCalculator.new(@faction).compute
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
