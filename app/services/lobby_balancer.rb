# Automatically balances a lobby by swapping players between teams
# to minimize the win prediction difference from 50/50
#
# Uses the same adaptive CR/ML weighting as LobbyWinPredictor
# Also considers faction experience - prefers swapping players to factions they play
#
# Strategy:
# 1. Find optimal final assignment using ALL possible swap combinations
# 2. Identify minimal set of swaps to achieve that assignment
# 3. Faction experience is factored into player scores (like LobbyWinPredictor)
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
  FACTION_GAMES_FOR_FULL_CONFIDENCE = LobbyWinPredictor::FACTION_GAMES_FOR_FULL_CONFIDENCE
  MAX_FACTION_PENALTY_POINTS = LobbyWinPredictor::MAX_FACTION_PENALTY_POINTS

  # Minimum improvement threshold to consider a swap worth making (in score units)
  MIN_IMPROVEMENT_THRESHOLD = 0.5

  attr_reader :lobby

  def initialize(lobby)
    @lobby = lobby
    @faction_experience_cache = {}
    preload_faction_experience
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
      current_diff = calculate_team_diff(good_slots, good_factions, evil_slots, evil_factions)

      # If already balanced enough, stop
      break if current_diff.abs < 1.0

      best_swap = nil
      best_new_diff = current_diff.abs

      # Try ALL possible swaps (any good player with any evil player)
      good_data.each_with_index do |gd, gi|
        evil_data.each_with_index do |ed, ei|
          # Simulate swap: good[gi] goes to evil faction[ei], evil[ei] goes to good faction[gi]
          new_good_slots = good_slots.dup
          new_evil_slots = evil_slots.dup
          new_good_slots[gi] = ed[:slot]
          new_evil_slots[ei] = gd[:slot]

          new_diff = calculate_team_diff(new_good_slots, good_factions, new_evil_slots, evil_factions)

          # Check if this improves balance
          if new_diff.abs < best_new_diff - 0.01
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
      break if improvement < 0.1 && !swaps.empty? # Stop if marginal improvement after first swap

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

  def preload_faction_experience
    player_ids = lobby.lobby_players.filter_map(&:player_id)
    return if player_ids.empty?

    counts = Appearance.joins(:match)
      .where(player_id: player_ids, matches: { ignored: false })
      .group(:player_id, :faction_id)
      .count

    counts.each do |(player_id, faction_id), count|
      @faction_experience_cache[[player_id, faction_id]] = count
    end
  end

  def faction_experience(player_id, faction_id)
    @faction_experience_cache[[player_id, faction_id]] || 0
  end

  def extract_slot_data(lp)
    if lp.is_new_player? && lp.player_id.nil?
      { player_id: nil, is_new_player: true, cr: NewPlayerDefaults.custom_rating, ml: NewPlayerDefaults.ml_score, games: 0 }
    elsif lp.player
      { player_id: lp.player_id, is_new_player: false, cr: lp.player.custom_rating || 1300, ml: lp.player.ml_score || 50, games: lp.player.custom_rating_games_played || 0 }
    else
      { player_id: nil, is_new_player: false, cr: nil, ml: nil, games: 0 }
    end
  end

  def calculate_team_diff(good_slots, good_factions, evil_slots, evil_factions)
    good_scores = good_slots.each_with_index.filter_map do |slot, i|
      compute_score_for_slot(slot, good_factions[i])
    end

    evil_scores = evil_slots.each_with_index.filter_map do |slot, i|
      compute_score_for_slot(slot, evil_factions[i])
    end

    return 0 if good_scores.empty? || evil_scores.empty?

    good_avg = good_scores.sum / good_scores.size
    evil_avg = evil_scores.sum / evil_scores.size
    good_avg - evil_avg
  end

  def compute_score_for_slot(slot, faction)
    return nil if slot[:cr].nil?

    cr = slot[:cr]
    ml = slot[:ml]
    games = slot[:games]

    cr_weight, ml_weight = weights_for_games(games)
    cr_norm = normalize_cr(cr)
    base_score = (cr_norm * cr_weight + ml * ml_weight) / 100.0

    # Apply faction experience adjustment if we have a player
    if slot[:player_id] && faction
      faction_games = faction_experience(slot[:player_id], faction.id)
      apply_faction_confidence(base_score, faction_games)
    else
      base_score
    end
  end

  def apply_faction_confidence(score, faction_games)
    confidence = 1 - Math.exp(-faction_games.to_f / FACTION_GAMES_FOR_FULL_CONFIDENCE)
    penalty = (1 - confidence) * MAX_FACTION_PENALTY_POINTS
    score - penalty
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
end
