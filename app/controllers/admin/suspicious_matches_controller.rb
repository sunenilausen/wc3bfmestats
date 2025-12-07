# frozen_string_literal: true

module Admin
  class SuspiciousMatchesController < BaseController
    before_action :authorize_admin

    def index
      @suspicious_matches = SuspiciousMatchFinder.new.call
    end

    private

    def authorize_admin
      authorize! :manage, :suspicious_matches
    end
  end
end
