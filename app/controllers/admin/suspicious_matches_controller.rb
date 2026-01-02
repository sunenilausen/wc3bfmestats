# frozen_string_literal: true

module Admin
  class SuspiciousMatchesController < BaseController
    before_action :authorize_admin

    DEFAULT_LIMIT = 100

    def index
      @show_all = params[:all] == "true"
      limit = @show_all ? nil : DEFAULT_LIMIT
      @suspicious_matches = SuspiciousMatchFinder.new(limit: limit).call
    end

    def review
      match = Match.find(params[:id])
      match.update!(reviewed: true)
      redirect_to admin_suspicious_matches_path, notice: "Match marked as reviewed"
    end

    private

    def authorize_admin
      authorize! :manage, :suspicious_matches
    end
  end
end
