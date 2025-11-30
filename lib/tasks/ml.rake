namespace :ml do
  desc "Train ML prediction model and recalculate all player ML scores"
  task train: :environment do
    puts "=" * 60
    puts "ML Score Training"
    puts "=" * 60

    puts "\nTraining prediction model..."
    PredictionModelTrainer.new.train

    weights = PredictionWeight.current
    puts "\nModel trained!"
    puts "  Accuracy: #{weights.accuracy}%"
    puts "  Games trained on: #{weights.games_trained_on}"
    puts "\nWeights:"
    weights.weights_hash.except(:bias).sort_by { |_, v| -v.abs }.each do |key, value|
      puts "  #{key.to_s.ljust(28)}: #{value >= 0 ? '+' : ''}#{value.round(6)}"
    end
    puts "  #{'bias'.ljust(28)}: #{weights.bias >= 0 ? '+' : ''}#{weights.bias.round(6)}"

    puts "\nRecalculating ML scores for all players..."
    MlScoreRecalculator.new.call

    puts "\nDone! ML scores recalculated for #{Player.count} players."
  end

  desc "Recalculate ML scores using current weights (no retraining)"
  task recalculate: :environment do
    puts "Recalculating ML scores using current weights..."

    weights = PredictionWeight.current
    puts "Using model with accuracy: #{weights.accuracy}%"

    MlScoreRecalculator.new.call

    puts "Done! ML scores recalculated for #{Player.count} players."
  end

  desc "Show current ML model weights"
  task weights: :environment do
    weights = PredictionWeight.current

    puts "=" * 60
    puts "Current ML Model Weights"
    puts "=" * 60
    puts "Accuracy: #{weights.accuracy}%"
    puts "Games trained on: #{weights.games_trained_on}"
    puts "Last trained: #{weights.last_trained_at}"

    # Features actually used in MlScoreRecalculator with minimum weights
    min_weights = {
      elo: 0.001,
      hero_kill_contribution: 0.005,
      unit_kill_contribution: 0.005,
      castle_raze_contribution: 0.005,
      team_heal_contribution: 0.005,
      hero_uptime: 0.005
    }

    used_features = min_weights.keys

    # Typical ranges for each feature (deviation from baseline)
    ranges = {
      elo: { typical_range: 300, desc: "1200-1800" },
      hero_kd: { typical_range: 2.0, desc: "0.5-3.0" },
      hero_kill_contribution: { typical_range: 15.0, desc: "5%-35%" },
      unit_kill_contribution: { typical_range: 15.0, desc: "5%-35%" },
      castle_raze_contribution: { typical_range: 15.0, desc: "5%-35%" },
      team_heal_contribution: { typical_range: 15.0, desc: "5%-35%" },
      hero_uptime: { typical_range: 20.0, desc: "60%-100%" },
      games_played: { typical_range: 4.6, desc: "log(1)-log(100)" },
      enemy_elo_diff: { typical_range: 200.0, desc: "-200 to +200" }
    }

    puts "\n#{"Feature".ljust(28)} #{"Trained".rjust(10)} #{"Effective".rjust(10)} #{"Range".rjust(14)} #{"Impact".rjust(8)}"
    puts "-" * 76

    sorted_weights = weights.weights_hash.except(:bias).map do |key, value|
      effective = min_weights[key] ? [value, min_weights[key]].max : value
      range_info = ranges[key]
      impact = range_info ? (effective.abs * range_info[:typical_range]) : 0
      [key, value, effective, impact]
    end.sort_by { |_, _, _, impact| -impact }

    sorted_weights.each do |key, trained, effective, impact|
      range_info = ranges[key]
      impact = range_info ? (effective.abs * range_info[:typical_range]).round(3) : 0
      range_desc = range_info ? range_info[:desc] : "?"
      used_marker = used_features.include?(key) ? "" : " [NOT USED]"

      trained_str = "#{trained >= 0 ? '+' : ''}#{trained.round(4)}"
      effective_str = "#{effective >= 0 ? '+' : ''}#{effective.round(4)}"
      puts "#{key.to_s.ljust(28)} #{trained_str.rjust(10)} #{effective_str.rjust(10)} #{range_desc.rjust(14)} #{impact.to_s.rjust(8)}#{used_marker}"
    end

    puts "-" * 76
    puts "#{"bias".ljust(28)} #{(weights.bias >= 0 ? '+' : '') + weights.bias.round(6).to_s}"
    puts "\nEffective = max(trained, minimum). Impact = effective x typical_range"
  end

end
