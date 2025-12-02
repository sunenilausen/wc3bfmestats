# Automatically balances a lobby by swapping players between teams
# to minimize the win prediction difference from 50/50
#
# Uses the same adaptive CR/ML weighting as LobbyWinPredictor
#
class LobbyBalancer
  # Use same constants as LobbyWinPredictor
  GAMES_THRESHOLD = LobbyWinPredictor::GAMES_THRESHOLD
  NEW_PLAYER_CR_WEIGHT = LobbyWinPredictor::NEW_PLAYER_CR_WEIGHT
  NEW_PLAYER_ML_WEIGHT = LobbyWinPredictor::NEW_PLAYER_ML_WEIGHT
  EXPERIENCED_CR_WEIGHT = LobbyWinPredictor::EXPERIENCED_CR_WEIGHT
  EXPERIENCED_ML_WEIGHT = LobbyWinPredictor::EXPERIENCED_ML_WEIGHT
  CR_MIN = LobbyWinPredictor::CR_MIN
  CR_MAX = LobbyWinPredictor::CR_MAX

  attr_reader :lobby

  def initialize(lobby)
    @lobby = lobby
  end

  # Returns the best swap to make, or nil if already balanced
  # Format: { good_index: i, evil_index: j, improvement: delta }
  def find_best_swap
    good_players = lobby.lobby_players.select { |lp| lp.faction&.good? }.sort_by { |lp| lp.faction_id }
    evil_players = lobby.lobby_players.reject { |lp| lp.faction&.good? }.sort_by { |lp| lp.faction_id }

    # Calculate current scores
    good_scores = good_players.map { |lp| player_score(lp) }
    evil_scores = evil_players.map { |lp| player_score(lp) }

    current_diff = team_diff(good_scores, evil_scores).abs

    best_swap = nil
    best_improvement = 0

    # Try all possible swaps between good and evil players
    good_players.each_with_index do |good_lp, gi|
      evil_players.each_with_index do |evil_lp, ei|
        # Simulate swap
        new_good_scores = good_scores.dup
        new_evil_scores = evil_scores.dup
        new_good_scores[gi] = evil_scores[ei]
        new_evil_scores[ei] = good_scores[gi]

        new_diff = team_diff(new_good_scores, new_evil_scores).abs
        improvement = current_diff - new_diff

        if improvement > best_improvement
          best_improvement = improvement
          best_swap = {
            good_lobby_player_id: good_lp.id,
            evil_lobby_player_id: evil_lp.id,
            good_faction_id: good_lp.faction_id,
            evil_faction_id: evil_lp.faction_id,
            improvement: improvement.round(2),
            new_diff: new_diff.round(2)
          }
        end
      end
    end

    best_swap
  end

  # Returns all swaps needed to reach optimal balance
  # Performs greedy optimization - keeps swapping until no improvement
  def find_optimal_swaps
    good_players = lobby.lobby_players.select { |lp| lp.faction&.good? }.sort_by { |lp| lp.faction_id }
    evil_players = lobby.lobby_players.reject { |lp| lp.faction&.good? }.sort_by { |lp| lp.faction_id }

    # Build score arrays with player references
    good_data = good_players.map { |lp| { lp: lp, score: player_score(lp) } }
    evil_data = evil_players.map { |lp| { lp: lp, score: player_score(lp) } }

    swaps = []
    max_iterations = 25 # Prevent infinite loops

    max_iterations.times do
      good_scores = good_data.map { |d| d[:score] }
      evil_scores = evil_data.map { |d| d[:score] }
      current_diff = team_diff(good_scores, evil_scores).abs

      best_swap = nil
      best_improvement = 0

      good_data.each_with_index do |gd, gi|
        evil_data.each_with_index do |ed, ei|
          # Simulate swap
          new_good_scores = good_scores.dup
          new_evil_scores = evil_scores.dup
          new_good_scores[gi] = evil_scores[ei]
          new_evil_scores[ei] = good_scores[gi]

          new_diff = team_diff(new_good_scores, new_evil_scores).abs
          improvement = current_diff - new_diff

          if improvement > 0.01 && improvement > best_improvement
            best_improvement = improvement
            best_swap = { gi: gi, ei: ei }
          end
        end
      end

      break unless best_swap

      # Perform the swap in our data structures
      gi, ei = best_swap[:gi], best_swap[:ei]
      swaps << {
        good_lobby_player_id: good_data[gi][:lp].id,
        evil_lobby_player_id: evil_data[ei][:lp].id,
        good_faction_id: good_data[gi][:lp].faction_id,
        evil_faction_id: evil_data[ei][:lp].faction_id
      }

      # Swap scores
      good_data[gi][:score], evil_data[ei][:score] = evil_data[ei][:score], good_data[gi][:score]
      # Swap player references too
      good_data[gi][:lp], evil_data[ei][:lp] = evil_data[ei][:lp], good_data[gi][:lp]
    end

    swaps
  end

  # Execute the balance by updating lobby_players
  def balance!
    swaps = find_optimal_swaps
    return { success: true, swaps: [], message: "Already balanced" } if swaps.empty?

    ActiveRecord::Base.transaction do
      swaps.each do |swap|
        good_lp = LobbyPlayer.find(swap[:good_lobby_player_id])
        evil_lp = LobbyPlayer.find(swap[:evil_lobby_player_id])

        # Swap the players between factions
        good_player_id = good_lp.player_id
        good_is_new = good_lp.is_new_player?
        evil_player_id = evil_lp.player_id
        evil_is_new = evil_lp.is_new_player?

        good_lp.update!(player_id: evil_player_id, is_new_player: evil_is_new)
        evil_lp.update!(player_id: good_player_id, is_new_player: good_is_new)
      end
    end

    # Reload and get new prediction
    lobby.reload
    prediction = LobbyWinPredictor.new(lobby).predict

    {
      success: true,
      swaps: swaps,
      swaps_count: swaps.size,
      prediction: prediction,
      message: "Balanced with #{swaps.size} swap#{swaps.size == 1 ? '' : 's'}"
    }
  rescue => e
    { success: false, message: "Balance failed: #{e.message}" }
  end

  private

  def player_score(lp)
    if lp.is_new_player? && lp.player_id.nil?
      compute_score(NewPlayerDefaults.custom_rating, NewPlayerDefaults.ml_score, 0)
    elsif lp.player
      compute_score(
        lp.player.custom_rating || 1300,
        lp.player.ml_score || 50,
        lp.player.custom_rating_games_played || 0
      )
    else
      nil
    end
  end

  def compute_score(cr, ml, games)
    cr_weight, ml_weight = weights_for_games(games)
    cr_norm = normalize_cr(cr)
    (cr_norm * cr_weight + ml * ml_weight) / 100.0
  end

  def weights_for_games(games)
    if games < GAMES_THRESHOLD
      [NEW_PLAYER_CR_WEIGHT, NEW_PLAYER_ML_WEIGHT]
    else
      [EXPERIENCED_CR_WEIGHT, EXPERIENCED_ML_WEIGHT]
    end
  end

  def normalize_cr(cr)
    ((cr - CR_MIN) / (CR_MAX - CR_MIN).to_f * 100).clamp(0, 100)
  end

  def team_diff(good_scores, evil_scores)
    good_valid = good_scores.compact
    evil_valid = evil_scores.compact
    return 0 if good_valid.empty? || evil_valid.empty?

    good_avg = good_valid.sum / good_valid.size
    evil_avg = evil_valid.sum / evil_valid.size
    good_avg - evil_avg
  end
end
