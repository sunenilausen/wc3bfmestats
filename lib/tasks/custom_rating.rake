namespace :custom_rating do
  desc "Recalculate custom ratings for all matches chronologically"
  task recalculate: :environment do
    puts "=" * 60
    puts "Custom Rating Recalculator"
    puts "=" * 60
    puts
    puts "Settings:"
    puts "  Default rating: #{CustomRatingRecalculator::DEFAULT_RATING}"
    puts "  Bonus wins: #{CustomRatingRecalculator::MAX_BONUS_WINS}"
    max_bonus = CustomRatingRecalculator::MAX_BONUS_WINS
    puts "  Bonus per win: +#{max_bonus} (1st) down to +1 (#{max_bonus}th)"
    puts "  Total bonus possible: #{(1..max_bonus).sum} points"
    puts
    puts "K-factor:"
    puts "  Brand new (0 games): #{CustomRatingRecalculator::K_FACTOR_BRAND_NEW}"
    puts "  Gradually decreases to #{CustomRatingRecalculator::K_FACTOR_NORMAL} at #{CustomRatingRecalculator::GAMES_UNTIL_NORMAL_K} games"
    puts "  High rated (#{CustomRatingRecalculator::RATING_FOR_LOW_K}+): #{CustomRatingRecalculator::K_FACTOR_HIGH_RATED}"
    puts "  Permanent low K at: #{CustomRatingRecalculator::RATING_FOR_PERMANENT_LOW_K}+"
    puts

    player_count = Player.count
    match_count = Match.where(ignored: false).count

    puts "Players: #{player_count}"
    puts "Matches to process: #{match_count}"
    puts

    if match_count.zero?
      puts "No matches to process."
      next
    end

    puts "Resetting ratings and recalculating..."
    puts

    recalculator = CustomRatingRecalculator.new
    recalculator.call

    puts "=" * 60
    puts "Summary"
    puts "=" * 60
    puts "Matches processed: #{recalculator.matches_processed}"

    if recalculator.errors.any?
      puts
      puts "Errors (#{recalculator.errors.count}):"
      recalculator.errors.each { |e| puts "  - #{e}" }
    end

    puts
    puts "Top 10 Players by Custom Rating:"
    puts "-" * 40
    Player.where.not(custom_rating: nil).order(custom_rating: :desc).limit(10).each_with_index do |player, i|
      bonus_info = player.custom_rating_bonus_wins.to_i > 0 ? " (#{player.custom_rating_bonus_wins} bonus wins left)" : ""
      puts "#{i + 1}. #{player.nickname}: #{player.custom_rating.round}#{bonus_info}"
    end
    puts "=" * 60
  end
end
