# frozen_string_literal: true

class DevSessionsController < ApplicationController
  def create
    return head :forbidden unless Rails.env.development? || Rails.env.test?

    admin = User.find_by(role: "admin")
    if admin
      sign_in(admin)
      redirect_to root_path, notice: "Signed in as #{admin.email}"
    else
      redirect_to new_user_session_path, alert: "No admin user found"
    end
  end
end
