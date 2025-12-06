class FactionsController < ApplicationController
  load_and_authorize_resource except: %i[index]

  # GET /factions or /factions.json
  def index
    @factions = Faction.all
  end

  # GET /factions/1 or /factions/1.json
  def show
    @map_version = params[:map_version]
    @available_map_versions = Rails.cache.fetch([ "available_map_versions", StatsCacheKey.key ]) do
      Match.where(ignored: false)
        .where.not(map_version: nil)
        .distinct
        .pluck(:map_version)
        .sort_by do |v|
          # Extract major.minor and suffix (e.g., "4.5e" -> [4, 5, "e"])
          match = v.match(/^(\d+)\.(\d+)([a-zA-Z]*)/)
          if match
            [ match[1].to_i, match[2].to_i, match[3].to_s ]
          else
            [ 0, 0, v ]
          end
        end
        .reverse
    end

    cache_key = [ "faction_stats", @faction.id, @map_version, StatsCacheKey.key ]

    @stats = Rails.cache.fetch(cache_key + [ "basic" ]) do
      FactionStatsCalculator.new(@faction, map_version: @map_version).compute
    end

    event_stats = Rails.cache.fetch(cache_key + [ "events" ]) do
      FactionEventStatsCalculator.new(@faction, map_version: @map_version).compute
    end

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

    # Top 10 players by faction score for this faction
    @top_performers = Rails.cache.fetch(cache_key + [ "top_performers" ]) do
      PlayerFactionStat.where(faction: @faction)
        .where("games_played >= ?", PlayerFactionStatsCalculator::MIN_GAMES_FOR_RANKING)
        .where.not(faction_score: nil)
        .order(faction_score: :desc)
        .limit(10)
        .includes(:player)
    end
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
