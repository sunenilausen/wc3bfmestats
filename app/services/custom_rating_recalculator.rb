class CustomRatingRecalculator
  DEFAULT_RATING = 1300
  MAX_BONUS_WINS = 15         # Number of wins that get bonus points

  # Variable K-factor settings
  K_FACTOR_BRAND_NEW = 50     # K-factor for players with 0 games
  K_FACTOR_NORMAL = 30        # K-factor after 30 games
  K_FACTOR_HIGH_RATED = 20    # K-factor at 1800+ rating
  GAMES_UNTIL_NORMAL_K = 30   # Games until K drops from new player to normal
  RATING_FOR_LOW_K = 1800     # Rating threshold for lower K-factor
  RATING_FOR_PERMANENT_LOW_K = 2000  # Once reached, K stays at 10 permanently

  attr_reader :matches_processed, :errors

  def initialize
    @matches_processed = 0
    @errors = []
    # Track running stats per player for prediction calculation
    @player_stats = Hash.new do |h, k|
      h[k] = {
        contribution_ranks: [],  # array of contribution ranks (1-5)
        faction_ranks: Hash.new { |h2, k2| h2[k2] = [] },  # faction_id => array of ranks
        games_played: 0,
        faction_games: Hash.new(0)  # games played per faction
      }
    end
  end

  def call
    RatingRecalculationStatus.start!
    reset_all_ratings
    recalculate_all_matches
    self
  ensure
    RatingRecalculationStatus.finish!
  end

  # Process a single match incrementally (only if it's the latest chronologically)
  # Returns true if processed incrementally, false if full recalc is needed
  def self.process_match_if_latest(match)
    if match.ignored?
      Rails.logger.info "CustomRatingRecalculator: Match ##{match.id} is ignored, skipping"
      return false
    end

    # Check if this match is the latest in chronological order
    # Use reverse_chronological.first instead of chronological.last since the scope uses raw SQL
    latest_match = Match.where(ignored: false).reverse_chronological.first
    unless latest_match&.id == match.id
      Rails.logger.info "CustomRatingRecalculator: Match ##{match.id} is not the latest (latest is ##{latest_match&.id})"
      return false
    end

    # Check if all appearances have nil ratings (new match, not yet processed)
    already_processed = match.appearances.any? { |a| a.custom_rating.present? }
    if already_processed
      Rails.logger.info "CustomRatingRecalculator: Match ##{match.id} already has ratings, skipping"
      return false
    end

    # Reload match with associations needed for rating calculation
    match = Match.includes(appearances: %i[player faction], wc3stats_replay: []).find(match.id)

    Rails.logger.info "CustomRatingRecalculator: Processing match ##{match.id} incrementally"
    new.send(:calculate_and_update_ratings, match)
    Rails.logger.info "CustomRatingRecalculator: Finished processing match ##{match.id}"
    true
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

  # Bonus amount decreases from 30 (first win) to 2 (15th win) in steps of 2
  # Additionally scaled by how far below 1500 the player is
  # At 1300: full bonus, at 1400: 50% bonus, at 1500+: no bonus
  def bonus_for_win(bonus_wins_remaining, current_rating)
    return 0 if current_rating >= 1500

    # 15 wins remaining = 30 pts, 14 = 28, 13 = 26, ..., 1 = 2
    base_bonus = bonus_wins_remaining.clamp(0, MAX_BONUS_WINS) * 2
    # Scale by distance from 1500 (1300 = 100%, 1400 = 50%, 1500 = 0%)
    rating_scale = (1500 - current_rating) / (1500.0 - DEFAULT_RATING)
    (base_bonus * rating_scale).round
  end

  # Variable K-factor based on games played and rating
  def k_factor_for_player(player)
    # Permanent low K if player has ever reached 2000
    return K_FACTOR_HIGH_RATED if player.custom_rating_reached_2000?

    # Low K if currently at 1800+
    return K_FACTOR_HIGH_RATED if player.custom_rating >= RATING_FOR_LOW_K

    games_played = player.custom_rating_games_played.to_i

    # Gradually decrease K from 50 (brand new) to 30 (at 30 games)
    if games_played < GAMES_UNTIL_NORMAL_K
      # Linear interpolation: 50 at 0 games, 30 at 30 games
      progress = games_played.to_f / GAMES_UNTIL_NORMAL_K
      (K_FACTOR_BRAND_NEW - (K_FACTOR_BRAND_NEW - K_FACTOR_NORMAL) * progress).round
    else
      K_FACTOR_NORMAL
    end
  end

  def recalculate_all_matches
    matches = Match.includes(appearances: [ :player, :faction ])
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

  # Contribution bonus points
  CONTRIBUTION_BONUS_WIN = [ 2, 1, 1, 0, -1 ]   # 1st, 2nd, 3rd, 4th, 5th (winners)
  CONTRIBUTION_BONUS_LOSS = [ 1, 1, 0, -1, -1 ] # 1st, 2nd, 3rd, 4th, 5th (losers)

  # Ring Drop bonus for Fellowship
  RING_DROP_BONUS = 1
  RING_DROP_POWERED_BONUS = 1  # Extra +1 if 2+ evil main bases are alive
  RING_DROP_EVENT = "Ring Drop"
  FELLOWSHIP_FACTION = "Fellowship"

  # Evil main bases to check for Ring Powered bonus
  # If 2+ of these are alive at ring drop time, Fellowship gets +1 extra
  RING_POWERED_BASES = [ "Barad-Dur", "Morannon", "Minas Morgul" ].freeze

  def calculate_and_update_ratings(match)
    return if match.appearances.empty?

    good_appearances = match.appearances.select { |a| a.faction.good? }
    evil_appearances = match.appearances.select { |a| !a.faction.good? }

    return if good_appearances.empty? || evil_appearances.empty?

    # Skip contribution bonus if anyone has 0 unit kills (incomplete/broken data)
    skip_contribution_bonus = match.appearances.any? { |a| a.unit_kills == 0 }

    # Calculate team average ratings using regular CR
    # (Faction ratings are for display only, not used in CR calculation)
    good_avg = good_appearances.sum { |a| a.player&.custom_rating || DEFAULT_RATING } / good_appearances.size.to_f
    evil_avg = evil_appearances.sum { |a| a.player&.custom_rating || DEFAULT_RATING } / evil_appearances.size.to_f

    # Store prediction based on team ratings (before updating ratings)
    store_match_prediction(match, good_avg, evil_avg)

    # For draws, record appearance data but no rating changes
    if match.is_draw?
      store_draw_appearances(match, good_appearances, evil_appearances)
      return
    end

    # For early leaver matches, special handling:
    # - Early leaver gets 0 rating change
    # - All other players get 30% reduced rating change
    if match.has_early_leaver?
      store_early_leaver_appearances(match, good_appearances, evil_appearances, skip_contribution_bonus)
      return
    end

    # Calculate performance scores and rank players within each team
    good_ranked = rank_by_performance(good_appearances, match)
    evil_ranked = rank_by_performance(evil_appearances, match)

    # Calculate match experience factor (0.0 to 1.0) based on all players' games played
    # Matches with new players have reduced rating impact for everyone
    match_experience = calculate_match_experience(match.appearances)

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

      # Apply match experience factor to base change (reduce impact when new players present)
      base_change = (base_change * match_experience).round

      # Add individual bonus for wins if player has bonus wins remaining
      # Bonus scales down as player approaches 1500 rating
      new_player_bonus = 0
      if won && player.custom_rating_bonus_wins.to_i > 0
        new_player_bonus = bonus_for_win(player.custom_rating_bonus_wins, player.custom_rating)
      end

      # Calculate performance score and rank
      ranked_team = is_good ? good_ranked : evil_ranked
      rank_entry = ranked_team.find { |r| r[:appearance].id == appearance.id }
      rank_index = ranked_team.index { |r| r[:appearance].id == appearance.id } || (ranked_team.size - 1)
      perf_score = rank_entry ? rank_entry[:score] : 0.0

      # Add contribution bonus based on performance ranking (skip if anyone has 0 unit kills)
      contribution_bonus = 0
      unless skip_contribution_bonus
        contribution_bonus = calculate_contribution_bonus(rank_index, won)
      end

      # MVP bonus: +1 for having both top unit kills AND top hero kills on winning team
      mvp_bonus = 0
      is_mvp = false
      if won
        team_appearances = is_good ? good_appearances : evil_appearances
        mvp_bonus = calculate_mvp_bonus(appearance, team_appearances)
        is_mvp = mvp_bonus > 0
      end

      # Ring Drop bonus: +1 for Fellowship when Ring Drop event occurs
      # Additional +1 if 2+ evil main bases are alive at ring drop time
      ring_drop_bonus, has_ring_powered_drop = calculate_ring_drop_bonus(appearance, match)
      has_ring_drop = ring_drop_bonus > 0

      total_change = base_change + new_player_bonus + contribution_bonus + mvp_bonus + ring_drop_bonus

      appearance.custom_rating = player.custom_rating
      appearance.custom_rating_change = total_change

      # Store contribution/performance data for faster queries
      appearance.contribution_rank = rank_index + 1
      appearance.contribution_bonus = contribution_bonus + mvp_bonus + ring_drop_bonus
      appearance.is_mvp = is_mvp
      appearance.has_ring_drop = has_ring_drop
      appearance.has_ring_powered_drop = has_ring_powered_drop
      appearance.performance_score = perf_score.round(2)

      # Store historical rank and PERF scores at time of match
      store_historical_stats(appearance)

      # Store contribution percentages and kill stats
      team_appearances = is_good ? good_appearances : evil_appearances
      store_contribution_percentages(appearance, team_appearances)
      store_kill_stats(appearance, team_appearances)
      store_hero_base_losses(appearance, match)

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

      # Update running stats for ML score calculation (after saving match data)
      update_player_running_stats(appearance, team_appearances, match)
    end
  end

  # Calculate performance score for an appearance (uses same weights as MlScoreRecalculator)
  def performance_score(appearance, match)
    # Get team appearances for contribution calculations
    team_appearances = match.appearances.select { |a| a.faction.good? == appearance.faction.good? }
    # Use version-specific weights (4.6+ has different castle/base kill weights)
    weights = MlScoreRecalculator.version_46_plus?(match.map_version) ?
      MlScoreRecalculator::WEIGHTS_46_PLUS :
      MlScoreRecalculator::WEIGHTS_PRE_46

    score = 0.0

    # Hero kill contribution (capped at 10% per hero killed)
    if appearance.hero_kills && !appearance.ignore_hero_kills?
      team_hero_kills = team_appearances.sum { |a| (a.hero_kills && !a.ignore_hero_kills?) ? a.hero_kills : 0 }
      if team_hero_kills > 0
        raw_contrib = (appearance.hero_kills.to_f / team_hero_kills) * 100
        max_contrib = appearance.hero_kills * MlScoreRecalculator::HERO_KILL_CAP_PER_KILL
        hk_contrib = [ raw_contrib, max_contrib ].min
        score += (hk_contrib - 20.0) * weights[:hero_kill_contribution]
      end
    end

    # Unit kill contribution (no cap)
    if appearance.unit_kills && !appearance.ignore_unit_kills?
      team_unit_kills = team_appearances.sum { |a| (a.unit_kills && !a.ignore_unit_kills?) ? a.unit_kills : 0 }
      if team_unit_kills > 0
        uk_contrib = (appearance.unit_kills.to_f / team_unit_kills) * 100
        score += (uk_contrib - 20.0) * weights[:unit_kill_contribution]
      end
    end

    # Castle raze contribution (capped at 20% per castle razed)
    if appearance.castles_razed
      team_castles = team_appearances.sum { |a| a.castles_razed || 0 }
      if team_castles > 0
        raw_contrib = (appearance.castles_razed.to_f / team_castles) * 100
        max_contrib = appearance.castles_razed * MlScoreRecalculator::CASTLE_RAZE_CAP_PER_KILL
        cr_contrib = [ raw_contrib, max_contrib ].min
        score += (cr_contrib - 20.0) * weights[:castle_raze_contribution]
      end
    end

    # Main base destroyed contribution (capped at 20% per main base)
    if appearance.main_base_destroyed
      team_main_bases = team_appearances.sum { |a| a.main_base_destroyed || 0 }
      if team_main_bases > 0
        raw_contrib = (appearance.main_base_destroyed.to_f / team_main_bases) * 100
        max_contrib = appearance.main_base_destroyed * MlScoreRecalculator::MAIN_BASE_CAP_PER_KILL
        mb_contrib = [ raw_contrib, max_contrib ].min
        score += (mb_contrib - 20.0) * weights[:main_base_contribution]
      end
    end

    # Team heal contribution (capped at 40% per game)
    if appearance.team_heal && appearance.team_heal > 0
      team_heal_total = team_appearances.sum { |a| (a.team_heal && a.team_heal > 0) ? a.team_heal : 0 }
      if team_heal_total > 0
        raw_contrib = (appearance.team_heal.to_f / team_heal_total) * 100
        th_contrib = [ raw_contrib, MlScoreRecalculator::TEAM_HEAL_CAP_PER_GAME ].min
        score += (th_contrib - 20.0) * weights[:team_heal_contribution]
      end
    end

    # Hero uptime (0-100%)
    hero_uptime = calculate_hero_uptime(appearance, match)
    if hero_uptime
      score += (hero_uptime - 80.0) * weights[:hero_uptime]
    end

    score
  end

  # Calculate hero uptime for an appearance from replay events
  def calculate_hero_uptime(appearance, match)
    replay = match.wc3stats_replay
    return nil unless replay&.events&.any?

    faction = appearance.faction
    return nil unless faction

    match_length = replay.game_length || match.seconds
    return nil unless match_length && match_length > 0

    # Get core hero names (exclude extra heroes like Sauron)
    extra_heroes = FactionEventStatsCalculator::EXTRA_HEROES rescue []
    core_hero_names = faction.heroes.reject { |h| extra_heroes.include?(h) }
    return nil if core_hero_names.empty?

    # Get hero death events within match length
    hero_death_events = replay.events.select do |e|
      e["eventName"] == "heroDeath" && e["time"] && e["time"] <= match_length
    end

    total_seconds_alive = 0
    total_seconds_possible = 0

    core_hero_names.each do |hero_name|
      hero_events = hero_death_events.select do |event|
        fix_encoding(replay, event["args"]&.first) == hero_name
      end

      if hero_events.any?
        death_time = hero_events.map { |e| e["time"] }.compact.min
        total_seconds_alive += death_time if death_time
      else
        total_seconds_alive += match_length
      end
      total_seconds_possible += match_length
    end

    return nil if total_seconds_possible == 0

    (total_seconds_alive.to_f / total_seconds_possible * 100).round(1)
  end

  def fix_encoding(replay, str)
    return str if str.nil?
    replay.fix_encoding(str.gsub("\\", ""))
  end

  # Rank appearances by performance score (highest first)
  def rank_by_performance(appearances, match)
    appearances
      .map { |a| { appearance: a, score: performance_score(a, match) } }
      .sort_by { |r| -r[:score] }
  end

  # Calculate contribution bonus based on rank within team
  def calculate_contribution_bonus(rank_index, won)
    bonus_array = won ? CONTRIBUTION_BONUS_WIN : CONTRIBUTION_BONUS_LOSS
    bonus_array[rank_index] || 0
  end

  # Factions that get a 1.33x unit kill multiplier for MVP calculation (support factions)
  MVP_UNIT_KILL_BOOST_FACTIONS = [ "Minas Morgul", "Fellowship" ].freeze
  MVP_UNIT_KILL_BOOST = 1.5

  # MVP bonus: +1 for having both top unit kills AND top hero kills on team
  def calculate_mvp_bonus(appearance, team_appearances)
    # Check top unit kills (with 1.25x boost for Minas Morgul and Fellowship)
    valid_unit_kills = team_appearances.select { |a| a.unit_kills && !a.ignore_unit_kills? }
    return 0 unless valid_unit_kills.any?

    adjusted_unit_kills = valid_unit_kills.map do |a|
      base = a.unit_kills
      if MVP_UNIT_KILL_BOOST_FACTIONS.include?(a.faction.name)
        (base * MVP_UNIT_KILL_BOOST).round
      else
        base
      end
    end

    my_unit_kills = appearance.unit_kills
    if appearance.unit_kills && !appearance.ignore_unit_kills? && MVP_UNIT_KILL_BOOST_FACTIONS.include?(appearance.faction.name)
      my_unit_kills = (appearance.unit_kills * MVP_UNIT_KILL_BOOST).round
    end

    max_adjusted_unit_kills = adjusted_unit_kills.max
    has_top_unit_kills = my_unit_kills && my_unit_kills == max_adjusted_unit_kills

    return 0 unless has_top_unit_kills

    # Check top hero kills (must have strictly more than second place)
    valid_hero_kills = team_appearances.select { |a| a.hero_kills && !a.ignore_hero_kills? }
    return 0 unless valid_hero_kills.any?

    sorted_hero_kills = valid_hero_kills.map(&:hero_kills).sort.reverse
    max_hero_kills = sorted_hero_kills[0]
    second_hero_kills = sorted_hero_kills[1] || 0

    return 0 if max_hero_kills == 0
    return 0 unless appearance.hero_kills && !appearance.ignore_hero_kills?

    # Must have top hero kills AND strictly more than second place
    (appearance.hero_kills == max_hero_kills && max_hero_kills > second_hero_kills) ? 1 : 0
  end

  # Ring Drop bonus: +1 for Fellowship player when Ring Drop event occurs
  # Additional +1 if 2+ of Barad-Dur, Morannon, Minas Morgul are alive at ring drop time
  # Returns [bonus_amount, is_powered]
  def calculate_ring_drop_bonus(appearance, match)
    return [ 0, false ] unless appearance.faction&.name == FELLOWSHIP_FACTION

    replay = match.wc3stats_replay
    return [ 0, false ] unless replay&.events&.any?

    # Find Ring Drop event and its time
    ring_drop_event = replay.events.find do |e|
      e["eventName"] == "eventsTriggered" &&
        fix_encoding(replay, e["args"]&.first) == RING_DROP_EVENT
    end

    return [ 0, false ] unless ring_drop_event

    ring_drop_time = ring_drop_event["time"] || 0

    # Check how many evil main bases are alive at ring drop time
    bases_alive = count_evil_bases_alive_at(replay, ring_drop_time, match)
    is_powered = bases_alive >= 2

    bonus = RING_DROP_BONUS
    bonus += RING_DROP_POWERED_BONUS if is_powered

    [ bonus, is_powered ]
  end

  # Count how many of the 3 main evil bases (Barad-Dur, Morannon, Minas Morgul) are alive at given time
  # Check 2 seconds before ring drop to handle events that occur at same timestamp in unpredictable order
  RING_DROP_TIME_BUFFER = 2

  def count_evil_bases_alive_at(replay, time, match)
    match_length = replay.game_length || match.seconds
    return 3 unless match_length && match_length > 0

    # Check 2 seconds before ring drop time to handle same-timestamp events
    check_time = time - RING_DROP_TIME_BUFFER

    # Get all base death events up to the check time (excluding ring events)
    base_death_events = replay.events.select do |e|
      e["eventName"] != "heroDeath" &&
        !Faction::RING_EVENTS.include?(fix_encoding(replay, e["args"]&.first)) &&
        e["time"] && e["time"] <= check_time
    end

    # Count how many of the key evil bases have NOT died by this time
    bases_alive = 0
    RING_POWERED_BASES.each do |base_name|
      base_died = base_death_events.any? do |event|
        fix_encoding(replay, event["args"]&.first) == base_name
      end
      bases_alive += 1 unless base_died
    end

    bases_alive
  end

  # Calculate match experience factor (0.0 to 1.0) based on all players' games played
  # Returns 1.0 if all players have 30+ games, lower if new players are present
  def calculate_match_experience(appearances)
    return 1.0 if appearances.empty?

    experience_sum = appearances.sum do |a|
      games = a.player&.custom_rating_games_played.to_i
      [ games.to_f / GAMES_UNTIL_NORMAL_K, 1.0 ].min
    end

    experience_sum / appearances.size
  end

  # Store contribution percentages on appearance for faster queries
  # Note: These are raw percentages without caps, for display purposes
  # The performance_score method applies the 20% per kill cap separately
  def store_contribution_percentages(appearance, team_appearances)
    # Hero kill contribution (no cap - raw percentage for display)
    if appearance.hero_kills && !appearance.ignore_hero_kills?
      team_hero_kills = team_appearances.sum { |a| (a.hero_kills && !a.ignore_hero_kills?) ? a.hero_kills : 0 }
      if team_hero_kills > 0
        appearance.hero_kill_pct = (appearance.hero_kills.to_f / team_hero_kills * 100).round(1)
      end
    end

    # Unit kill contribution
    if appearance.unit_kills && !appearance.ignore_unit_kills?
      team_unit_kills = team_appearances.sum { |a| (a.unit_kills && !a.ignore_unit_kills?) ? a.unit_kills : 0 }
      if team_unit_kills > 0
        appearance.unit_kill_pct = (appearance.unit_kills.to_f / team_unit_kills * 100).round(1)
      end
    end

    # Castle raze contribution
    if appearance.castles_razed
      team_castles = team_appearances.sum { |a| a.castles_razed || 0 }
      if team_castles > 0
        appearance.castle_raze_pct = (appearance.castles_razed.to_f / team_castles * 100).round(1)
      end
    end

    # Main base destroyed contribution
    if appearance.main_base_destroyed
      team_main_bases = team_appearances.sum { |a| a.main_base_destroyed || 0 }
      if team_main_bases > 0
        appearance.main_base_pct = (appearance.main_base_destroyed.to_f / team_main_bases * 100).round(1)
      end
    end

    # Total heal contribution
    if appearance.total_heal && appearance.total_heal > 0
      team_heal = team_appearances.sum { |a| (a.total_heal && a.total_heal > 0) ? a.total_heal : 0 }
      if team_heal > 0
        appearance.heal_pct = (appearance.total_heal.to_f / team_heal * 100).round(1)
      end
    end

    # Team heal contribution (healing others)
    if appearance.team_heal && appearance.team_heal > 0
      team_team_heal = team_appearances.sum { |a| (a.team_heal && a.team_heal > 0) ? a.team_heal : 0 }
      if team_team_heal > 0
        appearance.team_heal_pct = (appearance.team_heal.to_f / team_team_heal * 100).round(1)
      end
    end
  end

  # Store historical rank and PERF scores at time of match
  def store_historical_stats(appearance)
    player_id = appearance.player_id
    faction_id = appearance.faction_id
    return unless player_id && faction_id

    # Calculate overall avg rank from previous matches
    overall_avg = Appearance.joins(:match)
      .where(player_id: player_id, matches: { ignored: false })
      .where.not(contribution_rank: nil)
      .where.not(id: appearance.id)
      .average(:contribution_rank)

    appearance.overall_avg_rank = overall_avg&.round(2)

    # Calculate faction-specific avg rank from previous matches
    faction_avg = Appearance.joins(:match)
      .where(player_id: player_id, faction_id: faction_id, matches: { ignored: false })
      .where.not(contribution_rank: nil)
      .where.not(id: appearance.id)
      .average(:contribution_rank)

    appearance.faction_avg_rank = faction_avg&.round(2)

    # Get current PERF scores
    player = appearance.player
    appearance.perf_score = player&.ml_score

    faction_stat = PlayerFactionStat.find_by(player_id: player_id, faction_id: faction_id)
    appearance.faction_perf_score = faction_stat&.faction_score
  end

  # Store top hero/unit kills flags
  def store_kill_stats(appearance, team_appearances)
    # Top hero kills
    if appearance.hero_kills && !appearance.ignore_hero_kills?
      team_with_hero = team_appearances.select { |a| a.hero_kills && !a.ignore_hero_kills? }
      if team_with_hero.any?
        max_hero = team_with_hero.map(&:hero_kills).max
        appearance.top_hero_kills = (appearance.hero_kills == max_hero && max_hero > 0)
      end
    end

    # Top unit kills
    if appearance.unit_kills && !appearance.ignore_unit_kills?
      team_with_unit = team_appearances.select { |a| a.unit_kills && !a.ignore_unit_kills? }
      if team_with_unit.any?
        max_unit = team_with_unit.map(&:unit_kills).max
        appearance.top_unit_kills = (appearance.unit_kills == max_unit)
      end
    end
  end

  # Store heroes and bases lost from replay events
  def store_hero_base_losses(appearance, match)
    replay = match.wc3stats_replay
    return unless replay&.events&.any?

    faction = appearance.faction
    return unless faction

    match_length = replay.game_length || match.seconds
    return unless match_length && match_length > 0

    # Heroes lost
    extra_heroes = FactionEventStatsCalculator::EXTRA_HEROES rescue []
    core_hero_names = faction.heroes.reject { |h| extra_heroes.include?(h) }

    if core_hero_names.any?
      hero_death_events = replay.events.select do |e|
        e["eventName"] == "heroDeath" && e["time"] && e["time"] <= match_length
      end

      heroes_died = 0
      core_hero_names.each do |hero_name|
        hero_events = hero_death_events.select do |event|
          replay.fix_encoding(event["args"]&.first&.gsub("\\", "")) == hero_name
        end
        heroes_died += 1 if hero_events.any?
      end

      appearance.heroes_lost = heroes_died
      appearance.heroes_total = core_hero_names.size
    end

    # Bases lost
    base_names = faction.bases
    return if base_names.empty? # Fellowship has no bases

    ring_events = Faction::RING_EVENTS rescue []
    base_death_events = replay.events.select do |e|
      e["eventName"] != "heroDeath" &&
        !ring_events.include?(replay.fix_encoding(e["args"]&.first&.gsub("\\", ""))) &&
        e["time"] && e["time"] <= match_length
    end

    # Filter end-game mass base deaths
    end_threshold = match_length - 30
    end_game_events = base_death_events.select { |e| e["time"] && e["time"] >= end_threshold }
    if end_game_events.size >= 3
      end_game_times = end_game_events.map { |e| e["time"] }
      if end_game_times.max - end_game_times.min <= 15
        base_death_events = base_death_events.reject { |e| e["time"] && e["time"] >= end_threshold }
      end
    end

    bases_died = 0
    base_names.each do |base_name|
      base_events = base_death_events.select do |event|
        replay.fix_encoding(event["args"]&.first&.gsub("\\", "")) == base_name
      end
      bases_died += 1 if base_events.any?
    end

    appearance.bases_lost = bases_died
    appearance.bases_total = base_names.size
  end

  # Constants matching LobbyWinPredictor
  GAMES_FOR_FULL_CR_TRUST = 30
  MAX_ML_CR_ADJUSTMENT = 200
  ML_BASELINE = 0  # 0-centered scale (0 = average)

  # Store match prediction using same logic as LobbyWinPredictor
  # Uses CR with ML score adjustment for new players, weighted by faction impact
  def store_match_prediction(match, good_avg, evil_avg)
    good_effective_crs = []
    evil_effective_crs = []

    match.appearances.each do |app|
      next unless app.faction
      player = app.player

      effective_cr = if player
        calculate_player_effective_cr(player)
      else
        # New player without match history
        calculate_effective_cr(
          NewPlayerDefaults.custom_rating,
          0,
          NewPlayerDefaults.ml_score
        )
      end

      # Apply faction impact weight
      faction_weight = LobbyWinPredictor::FACTION_IMPACT_WEIGHTS[app.faction.name] || LobbyWinPredictor::DEFAULT_FACTION_WEIGHT
      weighted_cr = effective_cr * faction_weight

      if app.faction.good?
        good_effective_crs << weighted_cr
      else
        evil_effective_crs << weighted_cr
      end
    end

    return if good_effective_crs.empty? || evil_effective_crs.empty?

    good_avg_effective = good_effective_crs.sum / good_effective_crs.size.to_f
    evil_avg_effective = evil_effective_crs.sum / evil_effective_crs.size.to_f

    # Convert CR difference to win probability (same as LobbyWinPredictor)
    # 100 CR difference ≈ 64% win chance for higher rated team
    cr_diff = good_avg_effective - evil_avg_effective
    good_win_probability = 1.0 / (1 + Math.exp(-cr_diff / 150.0))

    match.update_columns(
      predicted_good_win_pct: (good_win_probability * 100).round(1),
      predicted_good_avg_rating: good_avg.round(1),
      predicted_evil_avg_rating: evil_avg.round(1),
      predicted_good_score: good_avg_effective.round(1),
      predicted_evil_score: evil_avg_effective.round(1)
    )
  end

  # Calculate player effective CR using same formula as LobbyWinPredictor
  def calculate_player_effective_cr(player)
    stats = @player_stats[player.id]
    games_played = stats[:games_played]
    cr = player.custom_rating || DEFAULT_RATING
    ml_score = player.ml_score || ML_BASELINE

    calculate_effective_cr(cr, games_played, ml_score)
  end

  # Calculate effective CR with ML score adjustment for new players
  # Only applies penalty for new players with ML score < 0 (below average)
  # No bonus for any new player - trust their CR if they perform well
  def calculate_effective_cr(cr, games, ml_score)
    return cr.to_f if games >= GAMES_FOR_FULL_CR_TRUST

    # Only apply penalty if ML score is below baseline (0)
    # No bonus for new players at or above 0
    return cr.to_f if ml_score >= ML_BASELINE

    # ML score deviation from baseline (negative only at this point)
    ml_deviation = ml_score - ML_BASELINE

    # Penalty scales down as games increase
    adjustment_factor = 1.0 - (games.to_f / GAMES_FOR_FULL_CR_TRUST)

    # Scale deviation to CR adjustment (max -200 for ML score -50)
    ml_cr_adjustment = (ml_deviation / 50.0) * MAX_ML_CR_ADJUSTMENT * adjustment_factor

    cr + ml_cr_adjustment
  end

  # Update running stats for a player after processing a match appearance
  def update_player_running_stats(appearance, _team_appearances, _match)
    player = appearance.player
    return unless player

    stats = @player_stats[player.id]

    # Track contribution rank (1-5, already calculated in calculate_and_update_ratings)
    if appearance.contribution_rank
      stats[:contribution_ranks] << appearance.contribution_rank
      stats[:faction_ranks][appearance.faction_id] << appearance.contribution_rank
    end

    stats[:games_played] += 1
    stats[:faction_games][appearance.faction_id] += 1
  end

  # Store appearance data for early leaver matches
  # - Early leaver gets 0 rating change (even if won)
  # - All other players get 70% of normal rating change (30% less)
  def store_early_leaver_appearances(match, good_appearances, evil_appearances, skip_contribution_bonus)
    # Calculate performance rankings for contribution bonuses
    good_ranked = rank_by_performance(good_appearances, match)
    evil_ranked = rank_by_performance(evil_appearances, match)

    # Calculate match experience factor
    match_experience = calculate_match_experience(match.appearances)

    # Calculate team averages
    good_avg = good_appearances.sum { |a| a.player&.custom_rating || DEFAULT_RATING } / good_appearances.size.to_f
    evil_avg = evil_appearances.sum { |a| a.player&.custom_rating || DEFAULT_RATING } / evil_appearances.size.to_f

    match.appearances.each do |appearance|
      player = appearance.player
      next unless player&.custom_rating

      is_good = appearance.faction.good?
      won = (is_good && match.good_victory?) || (!is_good && !match.good_victory?)
      team_appearances = is_good ? good_appearances : evil_appearances
      ranked_team = is_good ? good_ranked : evil_ranked
      opponent_avg = is_good ? evil_avg : good_avg
      own_team_avg = is_good ? good_avg : evil_avg

      # Calculate what the normal rating change would be
      player_effective = (INDIVIDUAL_WEIGHT * player.custom_rating) + (TEAM_WEIGHT * own_team_avg)
      expected = 1.0 / (1.0 + 10**((opponent_avg - player_effective) / 400.0))
      actual = won ? 1 : 0

      k_factor = k_factor_for_player(player)
      base_change = (k_factor * (actual - expected)).round
      base_change = (base_change * match_experience).round

      # Calculate bonuses (same as normal)
      new_player_bonus = 0
      if won && player.custom_rating_bonus_wins.to_i > 0
        new_player_bonus = bonus_for_win(player.custom_rating_bonus_wins, player.custom_rating)
      end

      rank_entry = ranked_team.find { |r| r[:appearance].id == appearance.id }
      rank_index = ranked_team.index { |r| r[:appearance].id == appearance.id } || (ranked_team.size - 1)
      perf_score = rank_entry ? rank_entry[:score] : 0.0

      contribution_bonus = 0
      unless skip_contribution_bonus
        contribution_bonus = calculate_contribution_bonus(rank_index, won)
      end

      mvp_bonus = 0
      is_mvp = false
      if won
        mvp_bonus = calculate_mvp_bonus(appearance, team_appearances)
        is_mvp = mvp_bonus > 0
      end

      # Ring Drop bonus: +1 for Fellowship when Ring Drop event occurs
      # Additional +1 if 2+ evil main bases are alive at ring drop time
      ring_drop_bonus, has_ring_powered_drop = calculate_ring_drop_bonus(appearance, match)
      has_ring_drop = ring_drop_bonus > 0

      # Determine final rating change based on early leaver status
      # Early leaver matches: leaver gets 0, everyone else gets 30% reduced change
      if appearance.is_early_leaver?
        # Early leaver gets 0 rating change, no bonuses
        total_change = 0
      elsif won
        # Winners get 70% of normal rating change (30% less)
        reduced_base_change = (base_change * 0.7).round
        reduced_new_player_bonus = (new_player_bonus * 0.7).round
        total_change = reduced_base_change + reduced_new_player_bonus + contribution_bonus + mvp_bonus + ring_drop_bonus
      else
        # Losers get 70% of normal loss (30% less, base_change is negative)
        reduced_base_change = (base_change * 0.7).round
        total_change = reduced_base_change + contribution_bonus + ring_drop_bonus
      end

      # Store rating data
      appearance.custom_rating = player.custom_rating
      appearance.custom_rating_change = total_change
      appearance.contribution_rank = rank_index + 1
      appearance.contribution_bonus = contribution_bonus + mvp_bonus + ring_drop_bonus
      appearance.is_mvp = is_mvp
      appearance.has_ring_drop = has_ring_drop
      appearance.has_ring_powered_drop = has_ring_powered_drop
      appearance.performance_score = perf_score.round(2)

      store_historical_stats(appearance)
      store_contribution_percentages(appearance, team_appearances)
      store_kill_stats(appearance, team_appearances)
      store_hero_base_losses(appearance, match)

      player.custom_rating += total_change
      player.custom_rating_games_played = player.custom_rating_games_played.to_i + 1

      # Mark if player reaches 2000 (permanent low K)
      if player.custom_rating >= RATING_FOR_PERMANENT_LOW_K && !player.custom_rating_reached_2000?
        player.custom_rating_reached_2000 = true
      end

      # Decrement bonus wins if they won and had bonus wins remaining (only for non-early-leavers)
      if won && player.custom_rating_bonus_wins.to_i > 0 && !appearance.is_early_leaver?
        player.custom_rating_bonus_wins -= 1
      end

      player.save!
      appearance.save!

      update_player_running_stats(appearance, team_appearances, match)
    end
  end

  # Store appearance data for draws without rating changes
  def store_draw_appearances(match, good_appearances, evil_appearances)
    match.appearances.each do |appearance|
      player = appearance.player
      next unless player

      is_good = appearance.faction.good?
      team_appearances = is_good ? good_appearances : evil_appearances

      # Store current rating with zero change
      appearance.custom_rating = player.custom_rating
      appearance.custom_rating_change = 0

      # Store contribution data (for display purposes)
      store_contribution_percentages(appearance, team_appearances)
      store_kill_stats(appearance, team_appearances)
      store_hero_base_losses(appearance, match)
      store_historical_stats(appearance)

      # Increment games played (draws still count as games)
      player.custom_rating_games_played = player.custom_rating_games_played.to_i + 1

      player.save!
      appearance.save!

      # Update running stats
      update_player_running_stats(appearance, team_appearances, match)
    end
  end
end
