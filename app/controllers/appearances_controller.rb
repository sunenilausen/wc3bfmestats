class AppearancesController < ApplicationController
  # GET /appearances or /appearances.json
  def index
    @appearances = Appearance.all
  end

  # GET /appearances/1 or /appearances/1.json
  def show
    @appearance = Appearance.find(params[:id])
  end
end
