class Wc3statsReplaysController < ApplicationController
  load_and_authorize_resource except: %i[index]

  # GET /wc3stats_replays or /wc3stats_replays.json
  def index
    @wc3stats_replays = Wc3statsReplay.all
  end

  # GET /wc3stats_replays/1 or /wc3stats_replays/1.json
  def show
  end

  # GET /wc3stats_replays/new
  def new
  end

  # GET /wc3stats_replays/1/edit
  def edit
  end

  # POST /wc3stats_replays or /wc3stats_replays.json
  def create
    respond_to do |format|
      if @wc3stats_replay.save
        format.html { redirect_to @wc3stats_replay, notice: "Wc3stats replay was successfully created." }
        format.json { render :show, status: :created, location: @wc3stats_replay }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @wc3stats_replay.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /wc3stats_replays/1 or /wc3stats_replays/1.json
  def update
    respond_to do |format|
      if @wc3stats_replay.update(wc3stats_replay_params)
        format.html { redirect_to @wc3stats_replay, notice: "Wc3stats replay was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @wc3stats_replay }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @wc3stats_replay.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /wc3stats_replays/1 or /wc3stats_replays/1.json
  def destroy
    @wc3stats_replay.destroy!

    respond_to do |format|
      format.html { redirect_to wc3stats_replays_path, notice: "Wc3stats replay was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

    # Only allow a list of trusted parameters through.
    def wc3stats_replay_params
      params.expect(wc3stats_replay: [ :body, :wc3stats_replay_id ])
    end
end
