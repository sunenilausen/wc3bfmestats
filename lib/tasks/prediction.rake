namespace :prediction do
  desc "Refit the prediction calibration factor (PredictionCalibrator::K) and show how it scores"
  task calibrate: :environment do
    matches = Match.where(ignored: false, is_draw: false)
                   .where.not(predicted_good_win_pct: nil)
                   .chronological.to_a

    if matches.empty?
      puts "No matches with stored predictions."
      next
    end

    puts "Matches with a stored prediction: #{matches.size}"
    puts

    puts "Best-fit stretch factor K"
    puts "-" * 60
    { "all" => matches, "last 400" => matches.last(400), "last 200" => matches.last(200) }.each do |label, set|
      k = PredictionCalibrator.fit(set)
      puts "  #{label.ljust(10)} n=#{set.size.to_s.rjust(5)}  K=#{k.round(2)}  (equivalent CR divisor #{(PredictionCalibrator::RAW_DIVISOR / k).round})"
    end
    puts "  currently in use: K=#{PredictionCalibrator::K}"
    puts

    puts "Walk-forward validation (fit on the past, score the next 200)"
    puts "-" * 60
    base_total = 0.0
    calibrated_total = 0.0
    scored = 0
    (600...matches.size).step(200) do |i|
      train = matches[0...i]
      test = matches[i, 200] || []
      next if test.size < 50

      k = PredictionCalibrator.fit(train)
      base = brier(test) { |pct| pct }
      calibrated = brier(test) { |pct| stretch(pct, k) }
      puts "  train<#{i.to_s.ljust(5)} K=#{k.round(2)}  test n=#{test.size.to_s.rjust(3)}  Brier #{base.round(4)} -> #{calibrated.round(4)}"

      base_total += base * test.size
      calibrated_total += calibrated * test.size
      scored += test.size
    end
    if scored.positive?
      puts "  TOTAL out-of-sample Brier #{(base_total / scored).round(4)} -> #{(calibrated_total / scored).round(4)} (n=#{scored})"
      puts "  (lower is better)"
    end
    puts

    puts "Reliability with K=#{PredictionCalibrator::K}"
    puts "-" * 60
    puts "  #{'raw'.rjust(10)} #{'calibrated'.rjust(12)} #{'actual'.rjust(10)} #{'n'.rjust(6)}"
    buckets = matches.group_by do |m|
      confidence = [ m.predicted_good_win_pct, 100 - m.predicted_good_win_pct ].max
      [ ((confidence - 50) / 5).floor, 8 ].min
    end
    buckets.keys.sort.each do |bucket|
      rows = buckets[bucket]
      raw = rows.sum { |m| [ m.predicted_good_win_pct, 100 - m.predicted_good_win_pct ].max } / rows.size
      calibrated = rows.sum { |m|
        c = PredictionCalibrator.calibrate(m.predicted_good_win_pct)
        [ c, 100 - c ].max
      } / rows.size
      actual = 100.0 * rows.count { |m| (m.predicted_good_win_pct >= 50) == m.good_victory? } / rows.size
      puts "  #{"#{50 + bucket * 5}-#{55 + bucket * 5}%".rjust(10)} #{"#{calibrated.round(1)}%".rjust(12)} #{"#{actual.round(1)}%".rjust(10)} #{rows.size.to_s.rjust(6)}   (raw #{raw.round(1)}%)"
    end
  end

  desc "Recompute the CR uncertainty table used for the win chance margin of error"
  task uncertainty: :environment do
    window = ENV.fetch("WINDOW", "30").to_i
    buckets = Hash.new { |h, k| h[k] = [] }

    Player.where("custom_rating_games_played >= ?", window + 5).find_each do |player|
      appearances = player.appearances.joins(:match).where(matches: { ignored: false })
                          .merge(Match.chronological)
                          .select(:custom_rating, :games_played_before_match).to_a

      appearances.each_with_index do |appearance, i|
        later = appearances[i + window]
        next unless later && appearance.custom_rating && later.custom_rating && appearance.games_played_before_match

        buckets[games_bucket(appearance.games_played_before_match)] << (later.custom_rating - appearance.custom_rating)
      end
    end

    puts "How much a player's CR moves over their next #{window} games"
    puts "-" * 60
    puts "  #{'games'.ljust(8)} #{'n'.rjust(6)} #{'mean drift'.rjust(11)} #{'SD'.rjust(7)}"
    %w[0-4 5-9 10-19 20-29 30-59 60-119 120+].each do |bucket|
      changes = buckets[bucket]
      next if changes.size < 20

      mean = changes.sum.to_f / changes.size
      sd = Math.sqrt(changes.sum { |c| (c - mean)**2 } / changes.size)
      puts "  #{bucket.ljust(8)} #{changes.size.to_s.rjust(6)} #{mean.round(1).to_s.rjust(11)} #{sd.round(1).to_s.rjust(7)}"
    end
    puts
    puts "SD feeds LobbyWinPredictor::CR_UNCERTAINTY_BY_GAMES."
    puts "Note: only players who went on to play #{window} more games can be measured, so"
    puts "the low-experience buckets are truncated - hence SURVIVORSHIP_INFLATION."
  end

  def games_bucket(games)
    case games
    when 0...5 then "0-4"
    when 5...10 then "5-9"
    when 10...20 then "10-19"
    when 20...30 then "20-29"
    when 30...60 then "30-59"
    when 60...120 then "60-119"
    else "120+"
    end
  end

  def stretch(pct, k)
    p = (pct / 100.0).clamp(0.001, 0.999)
    100.0 / (1 + Math.exp(-Math.log(p / (1 - p)) * k))
  end

  def brier(matches)
    matches.sum { |m|
      predicted = yield(m.predicted_good_win_pct) / 100.0
      outcome = m.good_victory? ? 1.0 : 0.0
      (predicted - outcome)**2
    } / matches.size
  end
end
