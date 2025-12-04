module Admin
  class PlayerMergesController < BaseController
    before_action :set_source_player
    before_action :authorize_merge!

    # GET /admin/players/:player_id/merge
    def new
      @players = Player.where.not(id: @source_player.id).order(:nickname)
    end

    # POST /admin/players/:player_id/merge
    def create
      @target_player = Player.find(params[:target_player_id])

      # Store info before merge
      source_name = @source_player.nickname
      source_matches = @source_player.matches.where(ignored: false).count

      result = PlayerMerger.new(@target_player, @source_player).merge

      if result.success?
        # Recalculate ratings after merge
        CustomRatingRecalculator.new.call
        MlScoreRecalculator.new.call

        redirect_to player_path(@target_player),
          notice: "Successfully merged #{source_name} (#{source_matches} matches) into #{@target_player.nickname}. Ratings recalculated."
      else
        redirect_to new_admin_player_merge_path(@source_player), alert: result.message
      end
    rescue ActiveRecord::RecordNotFound
      redirect_to new_admin_player_merge_path(@source_player), alert: "Target player not found."
    end

    private

    def set_source_player
      @source_player = Player.find_by_battletag_or_id(params[:player_id])
      unless @source_player
        redirect_to players_path, alert: "Player not found."
      end
    end

    def authorize_merge!
      authorize! :merge, @source_player
    end
  end
end
