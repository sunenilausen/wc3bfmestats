# Trains prediction weights using logistic regression on historical match data
# Uses gradient descent to learn optimal weights for predicting match outcomes
class PredictionModelTrainer
  LEARNING_RATE = 0.01
  ITERATIONS = 1000
  REGULARIZATION = 0.001  # L2 regularization to prevent overfitting

  def initialize
    @feature_stats = {}  # For normalization
  end

  def train
    # Gather training data from all non-ignored matches
    training_data = build_training_data
    return nil if training_data.empty?

    # Initialize weights
    weights = initialize_weights

    # Compute feature statistics for normalization
    compute_feature_stats(training_data)

    # Normalize features
    normalized_data = normalize_features(training_data)

    # Train using gradient descent
    ITERATIONS.times do |i|
      gradients = compute_gradients(normalized_data, weights)
      weights = update_weights(weights, gradients)
    end

    # Compute accuracy on training data
    accuracy = compute_accuracy(normalized_data, weights)

    # Save the new model
    save_model(weights, training_data.size, accuracy)
  end

  private

  def build_training_data
    data = []

    Match.where(ignored: false).includes(
      appearances: [:player, :faction],
      wc3stats_replay: {}
    ).find_each do |match|
      next unless match.wc3stats_replay.present?

      good_features = compute_team_features(match, true)
      evil_features = compute_team_features(match, false)

      next if good_features.nil? || evil_features.nil?

      # Feature difference: good - evil (positive means good is stronger)
      feature_diff = subtract_features(good_features, evil_features)

      # Label: 1 if good won, 0 if evil won
      label = match.good_victory? ? 1.0 : 0.0

      data << { features: feature_diff, label: label }
    end

    data
  end

  def compute_team_features(match, is_good)
    appearances = match.appearances.select { |a| a.faction.good? == is_good }
    return nil if appearances.empty?

    # Get player stats for each appearance
    player_stats = {}
    appearances.each do |app|
      next unless app.player_id

      # Use cached stats if available, otherwise compute
      stats = compute_player_stats_at_match(app.player, match)
      player_stats[app.player_id] = stats if stats
    end

    return nil if player_stats.empty?

    # Aggregate team features (average across players)
    {
      hero_kd: safe_average(player_stats.values.map { |s| s[:hero_kd] }),
      hero_kill_contribution: safe_average(player_stats.values.map { |s| s[:hero_kill_contribution] }),
      unit_kill_contribution: safe_average(player_stats.values.map { |s| s[:unit_kill_contribution] }),
      castle_raze_contribution: safe_average(player_stats.values.map { |s| s[:castle_raze_contribution] }),
      team_heal_contribution: safe_average(player_stats.values.map { |s| s[:team_heal_contribution] }),
      hero_uptime: safe_average(player_stats.values.map { |s| s[:hero_uptime] }),
      games_played: safe_average(player_stats.values.map { |s| s[:games_played] }),
      elo: safe_average(appearances.map(&:custom_rating).compact),
      enemy_elo_diff: safe_average(player_stats.values.map { |s| s[:enemy_elo_diff] })
    }
  end

  def compute_player_stats_at_match(player, match)
    # Get all appearances before this match for the player
    prior_appearances = player.appearances
      .joins(:match)
      .where(matches: { ignored: false })
      .where("matches.uploaded_at < ?", match.uploaded_at)
      .includes(:faction, :match, match: { appearances: :faction, wc3stats_replay: {} })

    return nil if prior_appearances.empty?

    # Compute stats from prior matches
    stats = PlayerStatsCalculator.new(player, prior_appearances).compute

    # Get event stats (hero K/D, uptime) - this is expensive so we approximate
    event_stats = compute_simple_event_stats(player, prior_appearances)

    # Use log scale for games played (diminishing returns)
    total_matches = stats[:total_matches] || 0
    games_played_log = total_matches > 0 ? Math.log(total_matches + 1) : 0

    {
      hero_kd: event_stats[:hero_kd] || 1.0,
      hero_kill_contribution: stats[:avg_hero_kill_contribution] || 20.0,
      unit_kill_contribution: stats[:avg_unit_kill_contribution] || 20.0,
      castle_raze_contribution: stats[:avg_castle_raze_contribution] || 20.0,
      team_heal_contribution: stats[:avg_team_heal_contribution] || 20.0,
      hero_uptime: event_stats[:hero_uptime] || 80.0,
      games_played: games_played_log,
      enemy_elo_diff: stats[:avg_enemy_elo_diff] || 0
    }
  end

  def compute_simple_event_stats(player, appearances)
    # Simplified event stats calculation for training efficiency
    # Uses appearance data rather than full replay parsing
    total_hero_kills = 0
    total_hero_deaths = 0
    total_hero_seconds_alive = 0
    total_hero_seconds_possible = 0

    appearances.each do |app|
      next if app.hero_kills.nil? || app.ignore_hero_kills?

      total_hero_kills += app.hero_kills

      # Estimate deaths and uptime from replay events if available
      replay = app.match.wc3stats_replay
      if replay&.events.present?
        faction = app.faction
        hero_names = faction.heroes.reject { |h| FactionEventStatsCalculator::EXTRA_HEROES.include?(h) }
        match_length = replay.game_length || app.match.seconds || 0

        hero_death_events = replay.events.select { |e| e["eventName"] == "heroDeath" && e["time"] && e["time"] <= match_length }

        hero_names.each do |hero_name|
          hero_events = hero_death_events.select { |e| replay.fix_encoding(e["args"]&.first&.gsub("\\", "")) == hero_name }

          if hero_events.any?
            death_time = hero_events.map { |e| e["time"] }.compact.min
            total_hero_seconds_alive += death_time if death_time
            total_hero_deaths += 1
          else
            total_hero_seconds_alive += match_length
          end
          total_hero_seconds_possible += match_length
        end
      end
    end

    hero_kd = total_hero_deaths > 0 ? (total_hero_kills.to_f / total_hero_deaths) : 2.0
    hero_uptime = total_hero_seconds_possible > 0 ? (total_hero_seconds_alive.to_f / total_hero_seconds_possible * 100) : 80.0

    {
      hero_kd: hero_kd.clamp(0.1, 10.0),
      hero_uptime: hero_uptime.clamp(0.0, 100.0)
    }
  end

  def subtract_features(a, b)
    {
      hero_kd: (a[:hero_kd] || 1.0) - (b[:hero_kd] || 1.0),
      hero_kill_contribution: (a[:hero_kill_contribution] || 20.0) - (b[:hero_kill_contribution] || 20.0),
      unit_kill_contribution: (a[:unit_kill_contribution] || 20.0) - (b[:unit_kill_contribution] || 20.0),
      castle_raze_contribution: (a[:castle_raze_contribution] || 20.0) - (b[:castle_raze_contribution] || 20.0),
      team_heal_contribution: (a[:team_heal_contribution] || 20.0) - (b[:team_heal_contribution] || 20.0),
      hero_uptime: (a[:hero_uptime] || 80.0) - (b[:hero_uptime] || 80.0),
      games_played: (a[:games_played] || 0) - (b[:games_played] || 0),
      elo: (a[:elo] || 1300) - (b[:elo] || 1300),
      enemy_elo_diff: (a[:enemy_elo_diff] || 0) - (b[:enemy_elo_diff] || 0)
    }
  end

  def safe_average(values)
    values = values.compact
    return nil if values.empty?
    values.sum.to_f / values.size
  end

  def initialize_weights
    {
      hero_kd: 0.0,
      hero_kill_contribution: 0.0,
      unit_kill_contribution: 0.0,
      castle_raze_contribution: 0.0,
      team_heal_contribution: 0.0,
      hero_uptime: 0.0,
      games_played: 0.0,
      elo: 0.0,
      enemy_elo_diff: 0.0,
      bias: 0.0
    }
  end

  def compute_feature_stats(data)
    features = data.map { |d| d[:features] }

    @feature_stats = {}
    %i[hero_kd hero_kill_contribution unit_kill_contribution castle_raze_contribution team_heal_contribution hero_uptime games_played elo enemy_elo_diff].each do |key|
      values = features.map { |f| f[key] }.compact
      next if values.empty?

      mean = values.sum / values.size.to_f
      std = Math.sqrt(values.map { |v| (v - mean)**2 }.sum / values.size.to_f)
      std = 1.0 if std < 0.001  # Avoid division by zero

      @feature_stats[key] = { mean: mean, std: std }
    end
  end

  def normalize_features(data)
    data.map do |d|
      normalized = {}
      d[:features].each do |key, value|
        if @feature_stats[key]
          normalized[key] = (value - @feature_stats[key][:mean]) / @feature_stats[key][:std]
        else
          normalized[key] = value
        end
      end
      { features: normalized, label: d[:label] }
    end
  end

  def sigmoid(z)
    1.0 / (1.0 + Math.exp(-z.clamp(-500, 500)))
  end

  def predict(features, weights)
    z = weights[:bias]
    features.each do |key, value|
      z += (weights[key] || 0.0) * (value || 0.0)
    end
    sigmoid(z)
  end

  def compute_gradients(data, weights)
    gradients = weights.keys.to_h { |k| [k, 0.0] }
    n = data.size.to_f

    data.each do |d|
      prediction = predict(d[:features], weights)
      error = prediction - d[:label]

      gradients[:bias] += error / n
      d[:features].each do |key, value|
        gradients[key] += (error * (value || 0.0)) / n
        # L2 regularization
        gradients[key] += REGULARIZATION * (weights[key] || 0.0) / n
      end
    end

    gradients
  end

  def update_weights(weights, gradients)
    new_weights = {}
    weights.each do |key, value|
      new_weights[key] = value - LEARNING_RATE * (gradients[key] || 0.0)
    end
    new_weights
  end

  def compute_accuracy(data, weights)
    correct = 0
    data.each do |d|
      prediction = predict(d[:features], weights)
      predicted_label = prediction >= 0.5 ? 1.0 : 0.0
      correct += 1 if predicted_label == d[:label]
    end
    (correct.to_f / data.size * 100).round(1)
  end

  def save_model(weights, games_count, accuracy)
    # Denormalize weights to work with raw features
    denormalized = denormalize_weights(weights)

    PredictionWeight.create!(
      hero_kd_weight: denormalized[:hero_kd],
      hero_kill_contribution_weight: denormalized[:hero_kill_contribution],
      unit_kill_contribution_weight: denormalized[:unit_kill_contribution],
      castle_raze_contribution_weight: denormalized[:castle_raze_contribution],
      team_heal_contribution_weight: denormalized[:team_heal_contribution],
      hero_uptime_weight: denormalized[:hero_uptime],
      games_played_weight: denormalized[:games_played],
      elo_weight: denormalized[:elo],
      enemy_elo_diff_weight: denormalized[:enemy_elo_diff],
      bias: denormalized[:bias],
      games_trained_on: games_count,
      accuracy: accuracy,
      last_trained_at: Time.current
    )
  end

  def denormalize_weights(weights)
    denormalized = { bias: weights[:bias] }

    %i[hero_kd hero_kill_contribution unit_kill_contribution castle_raze_contribution team_heal_contribution hero_uptime games_played elo enemy_elo_diff].each do |key|
      if @feature_stats[key]
        # w_denorm = w_norm / std
        # bias adjustment: bias -= w_norm * mean / std
        denormalized[key] = weights[key] / @feature_stats[key][:std]
        denormalized[:bias] -= weights[key] * @feature_stats[key][:mean] / @feature_stats[key][:std]
      else
        denormalized[key] = weights[key]
      end
    end

    denormalized
  end
end
