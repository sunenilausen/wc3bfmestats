class CustomRatingRecalculator
  DEFAULT_RATING = 1300
  MAX_BONUS_WINS = 20         # Number of wins that get bonus points

  # Variable K-factor settings
  K_FACTOR_NEW_PLAYER = 40    # K-factor for players with < 30 games
  K_FACTOR_NORMAL = 30        # K-factor after 30 games
  K_FACTOR_HIGH_RATED = 20    # K-factor at 1800+ rating
  GAMES_UNTIL_NORMAL_K = 30   # Games until K drops from new player to normal
  RATING_FOR_LOW_K = 1800     # Rating threshold for lower K-factor
  RATING_FOR_PERMANENT_LOW_K = 2000  # Once reached, K stays at 10 permanently

  attr_reader :matches_processed, :errors

  def initialize
    @matches_processed = 0
    @errors = []
  end

  def call
    reset_all_ratings
    recalculate_all_matches
    self
  end

  private

  def reset_all_ratings
    # Reset all players to their seed rating (or default)
    # Calculate bonus wins remaining based on seed
    Player.find_each do |player|
      seed = player.custom_rating_seed || DEFAULT_RATING
      player.update!(
        custom_rating: seed,
        custom_rating_bonus_wins: bonus_wins_for_seed(seed),
        custom_rating_games_played: 0,
        custom_rating_reached_2000: false
      )
    end

    # Clear all appearance custom rating data
    Appearance.update_all(custom_rating: nil, custom_rating_change: nil)
  end

  # Calculate how many bonus wins a player gets based on their seed
  # Default (1300) gets 20 bonus wins
  # Higher seeds get fewer bonus wins proportionally
  def bonus_wins_for_seed(seed)
    return 0 if seed >= 1500

    # Total bonus for 20 wins: 20+19+18+...+1 = 210 points
    # Default 1300 gets full 20 bonus wins
    # 1400 seed gets 10 bonus wins (half way to 1500)
    # Scale bonus wins based on how far from 1500
    ratio = (1500 - seed) / (1500.0 - DEFAULT_RATING)
    (MAX_BONUS_WINS * ratio).round.clamp(0, MAX_BONUS_WINS)
  end

  # Bonus amount decreases from 20 (first win) to 1 (20th win)
  def bonus_for_win(bonus_wins_remaining)
    bonus_wins_remaining.clamp(0, MAX_BONUS_WINS)
  end

  # Variable K-factor based on games played and rating
  def k_factor_for_player(player)
    # Permanent low K if player has ever reached 2000
    return K_FACTOR_HIGH_RATED if player.custom_rating_reached_2000?

    # Low K if currently at 1800+
    return K_FACTOR_HIGH_RATED if player.custom_rating >= RATING_FOR_LOW_K

    # New player K if < 30 games
    return K_FACTOR_NEW_PLAYER if player.custom_rating_games_played.to_i < GAMES_UNTIL_NORMAL_K

    # Normal K otherwise
    K_FACTOR_NORMAL
  end

  def recalculate_all_matches
    matches = Match.includes(appearances: [:player, :faction])
                   .where(ignored: false)
                   .chronological

    matches.each do |match|
      calculate_and_update_ratings(match)
      @matches_processed += 1
    rescue StandardError => e
      @errors << "Match ##{match.id}: #{e.message}"
    end
  end

  # Weight for individual rating vs team average in expected score calculation
  INDIVIDUAL_WEIGHT = 0.2  # 1/5 own rating
  TEAM_WEIGHT = 0.8        # 4/5 team average

  def calculate_and_update_ratings(match)
    return if match.appearances.empty?

    good_appearances = match.appearances.select { |a| a.faction.good? }
    evil_appearances = match.appearances.select { |a| !a.faction.good? }

    return if good_appearances.empty? || evil_appearances.empty?

    # Calculate team average ratings
    good_avg = good_appearances.sum { |a| a.player&.custom_rating.to_i } / good_appearances.size.to_f
    evil_avg = evil_appearances.sum { |a| a.player&.custom_rating.to_i } / evil_appearances.size.to_f

    # Apply changes to all players (each player uses their own K-factor)
    match.appearances.each do |appearance|
      player = appearance.player
      next unless player&.custom_rating

      is_good = appearance.faction.good?
      won = (is_good && match.good_victory?) || (!is_good && !match.good_victory?)

      # Calculate player's effective rating: 1/5 own + 4/5 team average
      own_team_avg = is_good ? good_avg : evil_avg
      opponent_avg = is_good ? evil_avg : good_avg
      player_effective = (INDIVIDUAL_WEIGHT * player.custom_rating) + (TEAM_WEIGHT * own_team_avg)

      # Expected score based on effective rating vs opponent team average
      expected = 1.0 / (1.0 + 10**((opponent_avg - player_effective) / 400.0))
      actual = won ? 1 : 0

      # Use player's individual K-factor
      k_factor = k_factor_for_player(player)
      base_change = (k_factor * (actual - expected)).round

      # Add individual bonus for wins if player has bonus wins remaining
      bonus = 0
      if won && player.custom_rating_bonus_wins.to_i > 0
        bonus = bonus_for_win(player.custom_rating_bonus_wins)
      end

      total_change = base_change + bonus

      appearance.custom_rating = player.custom_rating
      appearance.custom_rating_change = total_change

      player.custom_rating += total_change
      player.custom_rating_games_played = player.custom_rating_games_played.to_i + 1

      # Mark if player reaches 2000 (permanent low K)
      if player.custom_rating >= RATING_FOR_PERMANENT_LOW_K && !player.custom_rating_reached_2000?
        player.custom_rating_reached_2000 = true
      end

      # Decrement bonus wins if they won and had bonus wins remaining
      if won && player.custom_rating_bonus_wins.to_i > 0
        player.custom_rating_bonus_wins -= 1
      end

      player.save!
      appearance.save!
    end
  end
end
