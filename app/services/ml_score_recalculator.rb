# Recalculates ML scores for all players
class MlScoreRecalculator
  # Hardcoded weights (manually tuned, not auto-trained)
  # Note: elo removed to make ML score independent of CR (CR is weighted separately in predictions)
  # Pre-4.6 weights (no base kills available)
  WEIGHTS_PRE_46 = {
    hero_kill_contribution: 0.05,
    unit_kill_contribution: 0.05,
    castle_raze_contribution: 0.02,
    main_base_contribution: 0.0,     # Not available pre-4.6
    team_heal_contribution: 0.01,
    hero_uptime: 0.01
  }.freeze

  # 4.6+ weights (base kills available, castle kills weighted less)
  WEIGHTS_46_PLUS = {
    hero_kill_contribution: 0.05,
    unit_kill_contribution: 0.05,
    castle_raze_contribution: 0.01,
    main_base_contribution: 0.01,
    team_heal_contribution: 0.01,
    hero_uptime: 0.01
  }.freeze

  # Default weights for overall calculations (used when version not specified)
  WEIGHTS = WEIGHTS_46_PLUS

  # Check if map version is 4.6 or later
  def self.version_46_plus?(map_version)
    return false if map_version.blank?
    # Parse version like "4.5e", "4.6", "4.6a" etc.
    match = map_version.match(/^(\d+)\.(\d+)/)
    return false unless match
    major = match[1].to_i
    minor = match[2].to_i
    major > 4 || (major == 4 && minor >= 6)
  end

  # Contribution caps per game (same as PlayerStatsCalculator)
  HERO_KILL_CAP_PER_KILL = 10.0
  CASTLE_RAZE_CAP_PER_KILL = 20.0
  MAIN_BASE_CAP_PER_KILL = 20.0
  TEAM_HEAL_CAP_PER_GAME = 40.0

  def call
    player_ids = Player.pluck(:id)
    return if player_ids.empty?

    # Wrap in transaction so users can view the site with old data during recalculation
    ActiveRecord::Base.transaction do
      call_inner(player_ids)
    end

    # Recalculate tier thresholds based on new ML score distribution
    PlayerTierCalculator.call

    # Invalidate stats cache since ML scores affect lobby/player displays
    StatsCacheKey.invalidate!
  end

  def call_inner(player_ids)
    # Batch query: games played per player (exclude early leaver matches for stats)
    games_played = Appearance.joins(:match)
      .where(matches: { ignored: false, has_early_leaver: false })
      .group(:player_id)
      .count

    # Batch query: team totals per match for kill contribution calculation
    match_ids = Match.where(ignored: false, has_early_leaver: false).pluck(:id)

    # Get map versions for all matches to determine which weight set to use
    match_versions = Match.where(ignored: false, has_early_leaver: false).pluck(:id, :map_version).to_h

    # Hero kills team totals (excluding ignored)
    hero_kill_totals = Appearance.joins(:faction)
      .where(match_id: match_ids)
      .where.not(hero_kills: nil)
      .where(ignore_hero_kills: [ false, nil ])
      .group(:match_id, "factions.good")
      .pluck(:match_id, Arel.sql("factions.good"), Arel.sql("SUM(hero_kills)"))

    hero_kill_totals_by_match = {}
    hero_kill_totals.each do |match_id, is_good, hk|
      hero_kill_totals_by_match[match_id] ||= {}
      hero_kill_totals_by_match[match_id][is_good] = hk.to_i
    end

    # Unit kills team totals (excluding ignored)
    unit_kill_totals = Appearance.joins(:faction)
      .where(match_id: match_ids)
      .where.not(unit_kills: nil)
      .where(ignore_unit_kills: [ false, nil ])
      .group(:match_id, "factions.good")
      .pluck(:match_id, Arel.sql("factions.good"), Arel.sql("SUM(unit_kills)"))

    unit_kill_totals_by_match = {}
    unit_kill_totals.each do |match_id, is_good, uk|
      unit_kill_totals_by_match[match_id] ||= {}
      unit_kill_totals_by_match[match_id][is_good] = uk.to_i
    end

    # Batch query: castle raze team totals
    castle_team_totals = Appearance.joins(:faction)
      .where(match_id: match_ids)
      .where.not(castles_razed: nil)
      .group(:match_id, "factions.good")
      .pluck(:match_id, Arel.sql("factions.good"), Arel.sql("SUM(castles_razed)"))

    castle_totals_by_match = {}
    castle_team_totals.each do |match_id, is_good, cr|
      castle_totals_by_match[match_id] ||= {}
      castle_totals_by_match[match_id][is_good] = cr.to_i
    end

    # Batch query: main base destroyed team totals
    main_base_team_totals = Appearance.joins(:faction)
      .where(match_id: match_ids)
      .where.not(main_base_destroyed: nil)
      .group(:match_id, "factions.good")
      .pluck(:match_id, Arel.sql("factions.good"), Arel.sql("SUM(main_base_destroyed)"))

    main_base_totals_by_match = {}
    main_base_team_totals.each do |match_id, is_good, mb|
      main_base_totals_by_match[match_id] ||= {}
      main_base_totals_by_match[match_id][is_good] = mb.to_i
    end

    # Batch query: team heal team totals
    team_heal_totals = Appearance.joins(:faction)
      .where(match_id: match_ids)
      .where.not(team_heal: nil)
      .where("team_heal > 0")
      .group(:match_id, "factions.good")
      .pluck(:match_id, Arel.sql("factions.good"), Arel.sql("SUM(team_heal)"))

    team_heal_by_match = {}
    team_heal_totals.each do |match_id, is_good, th|
      team_heal_by_match[match_id] ||= {}
      team_heal_by_match[match_id][is_good] = th.to_i
    end

    # Get hero kill appearances (excluding ignored and early leaver)
    hero_kill_appearances = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false, has_early_leaver: false })
      .where.not(hero_kills: nil)
      .where(ignore_hero_kills: [ false, nil ])
      .pluck(:player_id, :match_id, "factions.good", :hero_kills)

    # Get unit kill appearances (excluding ignored and early leaver)
    unit_kill_appearances = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false, has_early_leaver: false })
      .where.not(unit_kills: nil)
      .where(ignore_unit_kills: [ false, nil ])
      .pluck(:player_id, :match_id, "factions.good", :unit_kills)

    # Get castle raze appearances separately (may have different nulls)
    castle_appearances = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false, has_early_leaver: false })
      .where.not(castles_razed: nil)
      .pluck(:player_id, :match_id, "factions.good", :castles_razed, "factions.name")

    # Get main base destroyed appearances separately (4.6+ only)
    main_base_appearances = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false, has_early_leaver: false })
      .where.not(main_base_destroyed: nil)
      .pluck(:player_id, :match_id, "factions.good", :main_base_destroyed, "factions.name")

    # Get team heal appearances separately
    team_heal_appearances = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false, has_early_leaver: false })
      .where.not(team_heal: nil)
      .where("team_heal > 0")
      .pluck(:player_id, :match_id, "factions.good", :team_heal)

    # Calculate average kill contributions per player
    # Track castle raze separately for pre-4.6 and 4.6+ (different weights)
    player_contributions = Hash.new { |h, k| h[k] = {
      hk_contribs: [], uk_contribs: [],
      cr_contribs_pre46: [], cr_contribs_46plus: [],  # Castle raze by version
      mb_contribs: [],  # Main base (4.6+ only)
      th_contribs: [], enemy_elo_diffs: []
    } }

    hero_kill_appearances.each do |player_id, match_id, is_good, hk|
      team_total = hero_kill_totals_by_match.dig(match_id, is_good)
      next unless team_total && team_total > 0

      # Cap at 10% per hero killed
      raw_contrib = (hk.to_f / team_total * 100)
      max_contrib = hk * HERO_KILL_CAP_PER_KILL
      player_contributions[player_id][:hk_contribs] << [ raw_contrib, max_contrib ].min
    end

    unit_kill_appearances.each do |player_id, match_id, is_good, uk|
      team_total = unit_kill_totals_by_match.dig(match_id, is_good)
      next unless team_total && team_total > 0

      player_contributions[player_id][:uk_contribs] << (uk.to_f / team_total * 100)
    end

    castle_appearances.each do |player_id, match_id, is_good, cr, faction_name|
      team_total = castle_totals_by_match.dig(match_id, is_good)
      next unless team_total && team_total > 0

      # Isengard adjustment: -1 castle for Grond (same as contribution ranking)
      player_castles = cr
      adjusted_team_total = team_total
      if faction_name == "Isengard"
        player_castles = [ player_castles - 1, 0 ].max
        adjusted_team_total = [ adjusted_team_total - 1, 0 ].max
      end
      next unless adjusted_team_total > 0

      # Cap at 20% per castle razed
      raw_contrib = (player_castles.to_f / adjusted_team_total * 100)
      max_contrib = player_castles * CASTLE_RAZE_CAP_PER_KILL
      capped_contrib = [ raw_contrib, max_contrib ].min

      # Track separately by version for different weights
      if MlScoreRecalculator.version_46_plus?(match_versions[match_id])
        player_contributions[player_id][:cr_contribs_46plus] << capped_contrib
      else
        player_contributions[player_id][:cr_contribs_pre46] << capped_contrib
      end
    end

    main_base_appearances.each do |player_id, match_id, is_good, mb, faction_name|
      team_total = main_base_totals_by_match.dig(match_id, is_good)
      next unless team_total && team_total > 0

      # Isengard adjustment: -1 base kill in 4.6+ (same as contribution ranking)
      player_bases = mb
      adjusted_team_total = team_total
      if faction_name == "Isengard" && MlScoreRecalculator.version_46_plus?(match_versions[match_id])
        player_bases = [ player_bases - 1, 0 ].max
        adjusted_team_total = [ adjusted_team_total - 1, 0 ].max
      end
      next unless adjusted_team_total > 0

      # Cap at 20% per main base destroyed (same as castle raze)
      raw_contrib = (player_bases.to_f / adjusted_team_total * 100)
      max_contrib = player_bases * MAIN_BASE_CAP_PER_KILL
      player_contributions[player_id][:mb_contribs] << [ raw_contrib, max_contrib ].min
    end

    team_heal_appearances.each do |player_id, match_id, is_good, th|
      team_total = team_heal_by_match.dig(match_id, is_good)
      next unless team_total && team_total > 0

      # Cap at 40% per game
      raw_contrib = (th.to_f / team_total * 100)
      player_contributions[player_id][:th_contribs] << [ raw_contrib, TEAM_HEAL_CAP_PER_GAME ].min
    end

    # Batch query: Custom ratings per match for enemy CR diff calculation
    cr_appearances = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false, has_early_leaver: false })
      .where.not(custom_rating: nil)
      .pluck(:player_id, :match_id, "factions.good", :custom_rating)

    # Group custom ratings by match and team
    match_team_crs = Hash.new { |h, k| h[k] = { true => [], false => [] } }
    cr_appearances.each do |player_id, match_id, is_good, cr|
      match_team_crs[match_id][is_good] << { player_id: player_id, cr: cr }
    end

    # Calculate enemy CR diff for each player appearance
    cr_appearances.each do |player_id, match_id, is_good, player_cr|
      enemy_team = match_team_crs[match_id][!is_good]
      next if enemy_team.empty?

      enemy_avg_cr = enemy_team.sum { |e| e[:cr] }.to_f / enemy_team.size
      player_contributions[player_id][:enemy_elo_diffs] << (player_cr - enemy_avg_cr)
    end

    # Batch compute event stats for all players (hero K/D)
    event_stats = batch_compute_event_stats

    # First pass: calculate raw ML scores for all players
    player_raw_scores = {}
    Player.find_each do |player|
      contribs = player_contributions[player.id]
      avg_hk = contribs[:hk_contribs].any? ? (contribs[:hk_contribs].sum / contribs[:hk_contribs].size) : 20.0
      avg_uk = contribs[:uk_contribs].any? ? (contribs[:uk_contribs].sum / contribs[:uk_contribs].size) : 20.0
      # Castle raze: separate averages for pre-4.6 and 4.6+ (different weights)
      avg_cr_pre46 = contribs[:cr_contribs_pre46].any? ? (contribs[:cr_contribs_pre46].sum / contribs[:cr_contribs_pre46].size) : 20.0
      avg_cr_46plus = contribs[:cr_contribs_46plus].any? ? (contribs[:cr_contribs_46plus].sum / contribs[:cr_contribs_46plus].size) : 20.0
      avg_mb = contribs[:mb_contribs].any? ? (contribs[:mb_contribs].sum / contribs[:mb_contribs].size) : 20.0
      avg_th = contribs[:th_contribs].any? ? (contribs[:th_contribs].sum / contribs[:th_contribs].size) : 20.0

      es = event_stats[player.id] || {}
      hero_uptime = es[:hero_uptime] || 80.0

      raw_score = 0.0
      raw_score += WEIGHTS_PRE_46[:hero_kill_contribution] * (avg_hk - 20.0)
      raw_score += WEIGHTS_PRE_46[:unit_kill_contribution] * (avg_uk - 20.0)
      # Castle raze: apply version-specific weights
      if contribs[:cr_contribs_pre46].any?
        raw_score += WEIGHTS_PRE_46[:castle_raze_contribution] * (avg_cr_pre46 - 20.0)
      end
      if contribs[:cr_contribs_46plus].any?
        raw_score += WEIGHTS_46_PLUS[:castle_raze_contribution] * (avg_cr_46plus - 20.0)
      end
      # Main base: only 4.6+ (weight is 0 in pre-4.6 anyway)
      raw_score += WEIGHTS_46_PLUS[:main_base_contribution] * (avg_mb - 20.0)
      raw_score += WEIGHTS_PRE_46[:team_heal_contribution] * (avg_th - 20.0)
      raw_score += WEIGHTS_PRE_46[:hero_uptime] * (hero_uptime - 80.0)

      sigmoid_value = 1.0 / (1.0 + Math.exp(-raw_score.clamp(-500, 500) * 0.5))
      ml_score = sigmoid_value * 100

      player_raw_scores[player.id] = ml_score
    end

    # Normalize scores so average = 0 (subtract 50 from sigmoid output, then shift to true average of 0)
    # This makes it easy to tell: positive = above average, negative = below average
    if player_raw_scores.any?
      # Convert from 0-100 scale to centered scale (subtract 50)
      centered_scores = player_raw_scores.transform_values { |v| v - 50.0 }

      # Calculate shift needed to make average exactly 0
      # Only average across players with games (not diluted by 0-game players)
      scores_with_games = centered_scores.select { |pid, _| games_played[pid].to_i > 0 }
      current_avg = scores_with_games.any? ? scores_with_games.values.sum / scores_with_games.size : 0.0

      # Apply shift and save normalized scores
      centered_scores.each do |player_id, centered_score|
        normalized_score = (centered_score - current_avg).round(1)
        Player.where(id: player_id).update_all(ml_score: normalized_score)
      end
    end
  end

  private

  # Batch compute event stats for all players efficiently
  def batch_compute_event_stats
    stats = Hash.new { |h, k| h[k] = { hero_kills: 0, hero_deaths: 0, hero_seconds_alive: 0, hero_seconds_possible: 0, base_seconds_alive: 0, base_seconds_possible: 0 } }

    # Build battletag to player_id mapping
    battletag_to_id = Player.pluck(:battletag, :id).to_h

    # Process all replays once
    Wc3statsReplay.includes(match: :appearances).find_each do |replay|
      next unless replay.match.present?
      next if replay.match.ignored?

      match_length = replay.game_length || replay.match.seconds
      next unless match_length && match_length > 0

      replay.players.each do |player_data|
        battletag = fix_encoding(replay, player_data["name"])
        player_id = battletag_to_id[battletag]
        next unless player_id

        slot = player_data["slot"]
        next unless slot.present? && slot >= 0 && slot <= 9

        faction_name = Wc3stats::MatchBuilder::SLOT_TO_FACTION[slot]
        next unless faction_name

        faction = Faction.find_by(name: faction_name)
        next unless faction

        # Get hero kills from appearance
        appearance = replay.match.appearances.find { |a| a.player_id == player_id }
        hero_kills = appearance&.hero_kills
        has_hero_kills_data = !hero_kills.nil? && !appearance&.ignore_hero_kills?

        if has_hero_kills_data
          stats[player_id][:hero_kills] += hero_kills

          # Count hero deaths
          core_hero_names = faction.heroes.reject { |h| PlayerEventStatsCalculator::EXTRA_HEROES.include?(h) }
          hero_death_events = replay.events.select { |e| e["eventName"] == "heroDeath" && e["time"] && e["time"] <= match_length }

          core_hero_names.each do |hero_name|
            hero_events = hero_death_events.select { |e| fix_encoding(replay, e["args"]&.first) == hero_name }

            if hero_events.any?
              death_time = hero_events.map { |e| e["time"] }.compact.min
              stats[player_id][:hero_seconds_alive] += death_time if death_time
              stats[player_id][:hero_deaths] += 1
            else
              stats[player_id][:hero_seconds_alive] += match_length
            end
            stats[player_id][:hero_seconds_possible] += match_length
          end
        end

        # Base stats
        next if faction.bases.empty?

        base_death_events = replay.events.select do |e|
          e["eventName"] != "heroDeath" &&
            !Faction::RING_EVENTS.include?(fix_encoding(replay, e["args"]&.first)) &&
            e["time"] && e["time"] <= match_length
        end

        faction.bases.each do |base_name|
          base_events = base_death_events.select { |e| fix_encoding(replay, e["args"]&.first) == base_name }

          if base_events.any?
            death_time = base_events.map { |e| e["time"] }.compact.min
            stats[player_id][:base_seconds_alive] += death_time if death_time
          else
            stats[player_id][:base_seconds_alive] += match_length
          end
          stats[player_id][:base_seconds_possible] += match_length
        end
      end
    end

    # Compute derived stats and save to Player model
    result = {}
    stats.each do |player_id, s|
      hero_kd = s[:hero_deaths] > 0 ? (s[:hero_kills].to_f / s[:hero_deaths]).round(2) : nil
      hero_up = s[:hero_seconds_possible] > 0 ? (s[:hero_seconds_alive].to_f / s[:hero_seconds_possible] * 100).round(1) : 80.0
      base_up = s[:base_seconds_possible] > 0 ? (s[:base_seconds_alive].to_f / s[:base_seconds_possible] * 100).round(1) : 80.0

      result[player_id] = {
        hero_kd_ratio: hero_kd,
        hero_uptime: hero_up,
        base_uptime: base_up
      }

      # Save to Player model for caching
      Player.where(id: player_id).update_all(
        hero_kd_ratio: hero_kd,
        hero_uptime: hero_up,
        base_uptime: base_up
      )
    end
    result
  end

  def fix_encoding(replay, str)
    return str if str.nil?
    replay.fix_encoding(str.gsub("\\", ""))
  end
end
