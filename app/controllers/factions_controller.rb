class FactionsController < ApplicationController
  load_and_authorize_resource except: %i[index]

  # GET /factions or /factions.json
  def index
    @factions = Faction.all
  end

  # GET /factions/1 or /factions/1.json
  def show
    @version_filter = params[:version_filter]
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

    # Parse version filter (format: "from:4.5e" or "only:4.5e")
    @map_version = nil
    @map_version_until = nil
    if @version_filter.present?
      if @version_filter.start_with?("only:")
        @map_version = @version_filter.sub("only:", "")
      elsif @version_filter.start_with?("from:")
        @map_version_until = @version_filter.sub("from:", "")
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

    cache_key = [ "faction_stats", @faction.id, @version_filter, StatsCacheKey.key ]

    # Determine map_versions parameter for calculators
    calculator_map_versions = (@map_version.present? || @map_version_until.present?) ? @filtered_map_versions : nil

    @stats = Rails.cache.fetch(cache_key + [ "basic" ]) do
      FactionStatsCalculator.new(@faction, map_versions: calculator_map_versions).compute
    end

    event_stats = Rails.cache.fetch(cache_key + [ "events" ]) do
      FactionEventStatsCalculator.new(@faction, map_versions: calculator_map_versions).compute
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

    # Top 10 players by average contribution rank (lowest = best)
    @top_rank_players = Rails.cache.fetch(cache_key + [ "top_rank_players" ]) do
      # Get player_ids with 10+ games for this faction
      eligible_player_ids = Appearance.joins(:match)
        .where(faction_id: @faction.id, matches: { ignored: false })
        .where.not(contribution_rank: nil)
        .group(:player_id)
        .having("COUNT(*) >= ?", PlayerFactionStatsCalculator::MIN_GAMES_FOR_RANKING)
        .pluck(:player_id)

      # Calculate average rank for eligible players
      avg_ranks = Appearance.joins(:match)
        .where(player_id: eligible_player_ids, faction_id: @faction.id, matches: { ignored: false })
        .where.not(contribution_rank: nil)
        .group(:player_id)
        .pluck(:player_id, Arel.sql("AVG(contribution_rank)"), Arel.sql("COUNT(*)"))
        .map { |pid, avg, count| { player_id: pid, avg_rank: avg.to_f.round(2), games: count } }
        .sort_by { |d| d[:avg_rank] }
        .first(10)

      # Load players
      player_ids = avg_ranks.map { |d| d[:player_id] }
      players_by_id = Player.where(id: player_ids).index_by(&:id)

      avg_ranks.map { |d| d.merge(player: players_by_id[d[:player_id]]) }
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
