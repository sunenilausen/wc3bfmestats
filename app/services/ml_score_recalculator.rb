# Recalculates ML scores for all players
class MlScoreRecalculator
  def call
    weights = PredictionWeight.current.weights_hash
    player_ids = Player.pluck(:id)
    return if player_ids.empty?

    # Batch query: games played per player
    games_played = Appearance.joins(:match)
      .where(matches: { ignored: false })
      .group(:player_id)
      .count

    # Batch query: team totals per match for kill contribution calculation
    match_ids = Match.where(ignored: false).pluck(:id)

    team_totals = Appearance.joins(:faction)
      .where(match_id: match_ids)
      .where.not(hero_kills: nil, unit_kills: nil)
      .group(:match_id, "factions.good")
      .pluck(:match_id, Arel.sql("factions.good"), Arel.sql("SUM(hero_kills)"), Arel.sql("SUM(unit_kills)"))

    team_totals_by_match = {}
    team_totals.each do |match_id, is_good, hk, uk|
      team_totals_by_match[match_id] ||= {}
      team_totals_by_match[match_id][is_good] = { hero_kills: hk.to_i, unit_kills: uk.to_i }
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

    # Get all player appearances with faction info
    player_appearances = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false })
      .where.not(hero_kills: nil, unit_kills: nil)
      .pluck(:player_id, :match_id, "factions.good", :hero_kills, :unit_kills)

    # Get castle raze appearances separately (may have different nulls)
    castle_appearances = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false })
      .where.not(castles_razed: nil)
      .pluck(:player_id, :match_id, "factions.good", :castles_razed)

    # Calculate average kill contributions per player
    player_contributions = Hash.new { |h, k| h[k] = { hk_contribs: [], uk_contribs: [], cr_contribs: [], enemy_elo_diffs: [] } }

    player_appearances.each do |player_id, match_id, is_good, hk, uk|
      team = team_totals_by_match.dig(match_id, is_good)
      next unless team

      if team[:hero_kills] > 0
        player_contributions[player_id][:hk_contribs] << (hk.to_f / team[:hero_kills] * 100)
      end
      if team[:unit_kills] > 0
        player_contributions[player_id][:uk_contribs] << (uk.to_f / team[:unit_kills] * 100)
      end
    end

    castle_appearances.each do |player_id, match_id, is_good, cr|
      team_total = castle_totals_by_match.dig(match_id, is_good)
      next unless team_total && team_total > 0

      player_contributions[player_id][:cr_contribs] << (cr.to_f / team_total * 100)
    end

    # Batch query: ELO ratings per match for enemy ELO diff calculation
    elo_appearances = Appearance.joins(:match, :faction)
      .where(matches: { ignored: false })
      .where.not(elo_rating: nil)
      .pluck(:player_id, :match_id, "factions.good", :elo_rating)

    # Group ELO ratings by match and team
    match_team_elos = Hash.new { |h, k| h[k] = { true => [], false => [] } }
    elo_appearances.each do |player_id, match_id, is_good, elo|
      match_team_elos[match_id][is_good] << { player_id: player_id, elo: elo }
    end

    # Calculate enemy ELO diff for each player appearance
    elo_appearances.each do |player_id, match_id, is_good, player_elo|
      enemy_team = match_team_elos[match_id][!is_good]
      next if enemy_team.empty?

      enemy_avg_elo = enemy_team.sum { |e| e[:elo] }.to_f / enemy_team.size
      player_contributions[player_id][:enemy_elo_diffs] << (player_elo - enemy_avg_elo)
    end

    # Batch compute event stats for all players (hero K/D)
    event_stats = batch_compute_event_stats

    # Update each player's ML score
    Player.find_each do |player|
      contribs = player_contributions[player.id]
      avg_hk = contribs[:hk_contribs].any? ? (contribs[:hk_contribs].sum / contribs[:hk_contribs].size) : 20.0
      avg_uk = contribs[:uk_contribs].any? ? (contribs[:uk_contribs].sum / contribs[:uk_contribs].size) : 20.0
      avg_cr = contribs[:cr_contribs].any? ? (contribs[:cr_contribs].sum / contribs[:cr_contribs].size) : 20.0
      avg_enemy_elo_diff = contribs[:enemy_elo_diffs].any? ? (contribs[:enemy_elo_diffs].sum / contribs[:enemy_elo_diffs].size) : 0
      total_matches = games_played[player.id] || 0

      es = event_stats[player.id] || {}
      hero_kd = es[:hero_kd_ratio] || 1.0

      elo = player.elo_rating || 1500

      raw_score = 0.0
      raw_score += weights[:elo] * (elo - 1500)
      raw_score += weights[:hero_kd] * (hero_kd - 1.0)
      raw_score += weights[:hero_kill_contribution] * (avg_hk - 20.0)
      raw_score += weights[:unit_kill_contribution] * (avg_uk - 20.0)
      raw_score += weights[:castle_raze_contribution] * (avg_cr - 20.0)
      raw_score += weights[:games_played] * total_matches
      raw_score += weights[:enemy_elo_diff] * avg_enemy_elo_diff

      sigmoid_value = 1.0 / (1.0 + Math.exp(-raw_score.clamp(-500, 500) * 0.5))
      raw_ml_score = sigmoid_value * 100

      # Apply confidence adjustment based on games played
      # Players with few games get pulled toward 50 (average)
      # Confidence reaches ~95% at 20 games, ~99% at 50 games
      confidence = 1.0 - Math.exp(-total_matches / 10.0)
      ml_score = (50.0 + (raw_ml_score - 50.0) * confidence).round(1)

      player.update_column(:ml_score, ml_score)
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

    # Compute derived stats
    result = {}
    stats.each do |player_id, s|
      result[player_id] = {
        hero_kd_ratio: s[:hero_deaths] > 0 ? (s[:hero_kills].to_f / s[:hero_deaths]).round(2) : nil,
        hero_uptime: s[:hero_seconds_possible] > 0 ? (s[:hero_seconds_alive].to_f / s[:hero_seconds_possible] * 100).round(1) : 80.0,
        base_uptime: s[:base_seconds_possible] > 0 ? (s[:base_seconds_alive].to_f / s[:base_seconds_possible] * 100).round(1) : 80.0
      }
    end
    result
  end

  def fix_encoding(replay, str)
    return str if str.nil?
    replay.fix_encoding(str.gsub("\\", ""))
  end
end
