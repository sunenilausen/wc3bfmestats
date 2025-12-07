# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    before_action :authorize_admin

    def index
    end

    private

    def authorize_admin
      authorize! :manage, :admin_dashboard
    end
  end
end
