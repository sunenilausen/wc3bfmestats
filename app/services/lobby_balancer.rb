# Automatically balances a lobby by swapping players between teams
# to minimize the win prediction difference from 50/50
#
# Uses CR with ML score adjustment for new players (same as LobbyWinPredictor)
#
# Strategy:
# 1. Find optimal final assignment using ALL possible swap combinations
# 2. Identify minimal set of swaps to achieve that assignment
#
class LobbyBalancer
  # Use same constants as LobbyWinPredictor
  GAMES_FOR_FULL_CR_TRUST = LobbyWinPredictor::GAMES_FOR_FULL_CR_TRUST
  MAX_ML_CR_ADJUSTMENT = LobbyWinPredictor::MAX_ML_CR_ADJUSTMENT
  ML_BASELINE = LobbyWinPredictor::ML_BASELINE

  # Minimum improvement threshold to consider a swap worth making (in CR units)
  MIN_IMPROVEMENT_THRESHOLD = 10

  attr_reader :lobby

  def initialize(lobby)
    @lobby = lobby
  end

  # Returns the best swap to make, or nil if already balanced
  # Format: { good_index: i, evil_index: j, improvement: delta }
  def find_best_swap
    swaps = find_optimal_swaps
    swaps.first
  end

  # Returns minimal swaps needed to reach optimal balance
  # Uses greedy optimization - finds the single best swap at each iteration
  def find_optimal_swaps
    good_players = lobby.lobby_players.select { |lp| lp.faction&.good? }.sort_by { |lp| lp.faction_id }
    evil_players = lobby.lobby_players.reject { |lp| lp.faction&.good? }.sort_by { |lp| lp.faction_id }

    return [] if good_players.empty? || evil_players.empty?

    good_factions = good_players.map(&:faction)
    evil_factions = evil_players.map(&:faction)

    # Extract player/new_player data from lobby_players
    # Use arrays of hashes that we can swap around
    good_data = good_players.each_with_index.map { |lp, i| { lp: lp, slot: extract_slot_data(lp), faction: good_factions[i] } }
    evil_data = evil_players.each_with_index.map { |lp, i| { lp: lp, slot: extract_slot_data(lp), faction: evil_factions[i] } }

    swaps = []
    max_iterations = 10 # Prevent infinite loops

    max_iterations.times do
      # Calculate current team diff
      good_slots = good_data.map { |d| d[:slot] }
      evil_slots = evil_data.map { |d| d[:slot] }
      current_diff = calculate_team_diff(good_slots, evil_slots, good_factions, evil_factions)

      # If already balanced enough, stop
      break if current_diff.abs < 20 # Within 20 CR is balanced

      best_swap = nil
      best_new_diff = current_diff.abs

      # Try ALL possible swaps (any good player with any evil player)
      good_data.each_with_index do |gd, gi|
        evil_data.each_with_index do |ed, ei|
          # Simulate swap: good[gi] goes to evil, evil[ei] goes to good
          new_good_slots = good_slots.dup
          new_evil_slots = evil_slots.dup
          new_good_slots[gi] = ed[:slot]
          new_evil_slots[ei] = gd[:slot]

          new_diff = calculate_team_diff(new_good_slots, new_evil_slots, good_factions, evil_factions)

          # Check if this improves balance
          if new_diff.abs < best_new_diff - 1
            best_new_diff = new_diff.abs
            best_swap = { gi: gi, ei: ei }
          end
        end
      end

      # If no improvement found, stop
      break unless best_swap

      # Check if improvement is significant enough
      improvement = current_diff.abs - best_new_diff
      break if improvement < MIN_IMPROVEMENT_THRESHOLD && swaps.empty?
      break if improvement < 5 && !swaps.empty? # Stop if marginal improvement after first swap

      gi, ei = best_swap[:gi], best_swap[:ei]

      # Record the swap using original lobby_player IDs
      swaps << {
        good_lobby_player_id: good_data[gi][:lp].id,
        evil_lobby_player_id: evil_data[ei][:lp].id,
        good_faction_id: good_factions[gi].id,
        evil_faction_id: evil_factions[ei].id
      }

      # Perform the swap in our data structures
      # The SLOTS swap (players move), but FACTIONS stay fixed
      good_data[gi][:slot], evil_data[ei][:slot] = evil_data[ei][:slot], good_data[gi][:slot]
      good_data[gi][:lp], evil_data[ei][:lp] = evil_data[ei][:lp], good_data[gi][:lp]
    end

    swaps
  end

  # Execute the balance by updating lobby_players
  def balance!
    swaps = find_optimal_swaps
    return { success: true, swaps: [], message: "Already balanced" } if swaps.empty?

    swap_details = []

    ActiveRecord::Base.transaction do
      swaps.each do |swap|
        good_lp = LobbyPlayer.includes(:player, :faction).find(swap[:good_lobby_player_id])
        evil_lp = LobbyPlayer.includes(:player, :faction).find(swap[:evil_lobby_player_id])

        # Record swap details before swapping
        swap_details << {
          player1: good_lp.player&.nickname || "New Player",
          faction1: good_lp.faction&.name,
          player2: evil_lp.player&.nickname || "New Player",
          faction2: evil_lp.faction&.name
        }

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
      swap_details: swap_details,
      swaps_count: swaps.size,
      prediction: prediction,
      message: "Balanced with #{swaps.size} swap#{swaps.size == 1 ? '' : 's'}"
    }
  rescue => e
    { success: false, message: "Balance failed: #{e.message}" }
  end

  private

  def extract_slot_data(lp)
    if lp.is_new_player? && lp.player_id.nil?
      {
        player_id: nil,
        is_new_player: true,
        cr: NewPlayerDefaults.custom_rating,
        ml_score: NewPlayerDefaults.ml_score,
        games: 0,
        player: nil
      }
    elsif lp.player
      {
        player_id: lp.player_id,
        is_new_player: false,
        cr: lp.player.custom_rating || 1300,
        ml_score: lp.player.ml_score || ML_BASELINE,
        games: lp.player.custom_rating_games_played || 0,
        player: lp.player
      }
    else
      { player_id: nil, is_new_player: false, cr: nil, ml_score: nil, games: 0, player: nil }
    end
  end

  def calculate_team_diff(good_slots, evil_slots, good_factions, evil_factions)
    good_crs = good_slots.each_with_index.filter_map do |slot, i|
      cr = calculate_effective_cr(slot)
      next nil unless cr
      cr += faction_familiarity_adjustment(slot[:player], good_factions[i])
      weight = LobbyWinPredictor::FACTION_IMPACT_WEIGHTS[good_factions[i]&.name] || LobbyWinPredictor::DEFAULT_FACTION_WEIGHT
      cr * weight
    end
    evil_crs = evil_slots.each_with_index.filter_map do |slot, i|
      cr = calculate_effective_cr(slot)
      next nil unless cr
      cr += faction_familiarity_adjustment(slot[:player], evil_factions[i])
      weight = LobbyWinPredictor::FACTION_IMPACT_WEIGHTS[evil_factions[i]&.name] || LobbyWinPredictor::DEFAULT_FACTION_WEIGHT
      cr * weight
    end

    return 0 if good_crs.empty? || evil_crs.empty?

    good_avg = good_crs.sum / good_crs.size
    evil_avg = evil_crs.sum / evil_crs.size
    good_avg - evil_avg
  end

  # Penalty for playing an unfamiliar faction (same logic as LobbyWinPredictor)
  def faction_familiarity_adjustment(player, faction)
    return 0 unless player && faction

    total_games = player.custom_rating_games_played.to_i
    return 0 if total_games < LobbyWinPredictor::MIN_FACTION_GAMES_THRESHOLD

    faction_stat = player.player_faction_stats.find_by(faction: faction)
    faction_games = faction_stat&.games_played.to_i

    avg_games = total_games / 10.0
    threshold = [ avg_games, LobbyWinPredictor::MIN_FACTION_GAMES_THRESHOLD.to_f ].max

    ratio = [ faction_games / threshold, 1.0 ].min
    eased = Math.sqrt(ratio)

    -((1.0 - eased) * LobbyWinPredictor::MAX_FACTION_FAMILIARITY_PENALTY)
  end

  # Calculate effective CR with ML score adjustment for new players
  def calculate_effective_cr(slot)
    return nil if slot[:cr].nil?

    cr = slot[:cr]
    games = slot[:games]
    ml_score = slot[:ml_score] || ML_BASELINE

    return cr.to_f if games >= GAMES_FOR_FULL_CR_TRUST

    # Calculate how much of the ML adjustment to apply (decreases as games increase)
    adjustment_factor = 1.0 - (games.to_f / GAMES_FOR_FULL_CR_TRUST)

    # ML score deviation from baseline (50)
    ml_deviation = ml_score - ML_BASELINE

    # Scale deviation to CR adjustment (-200 to +200)
    ml_cr_adjustment = (ml_deviation / 50.0) * MAX_ML_CR_ADJUSTMENT * adjustment_factor

    cr + ml_cr_adjustment
  end
end
