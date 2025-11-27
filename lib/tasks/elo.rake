namespace :elo do
  desc "Recalculate ELO ratings for all matches chronologically"
  task recalculate: :environment do
    puts "=" * 60
    puts "ELO Rating Recalculator"
    puts "=" * 60
    puts

    player_count = Player.count
    match_count = Match.count

    puts "Players: #{player_count}"
    puts "Matches to process: #{match_count}"
    puts

    if match_count.zero?
      puts "No matches to process."
      next
    end

    puts "Resetting ratings and recalculating..."
    puts

    recalculator = EloRecalculator.new
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
    puts "Top 10 Players by ELO:"
    puts "-" * 40
    Player.order(elo_rating: :desc).limit(10).each_with_index do |player, i|
      puts "#{i + 1}. #{player.nickname}: #{player.elo_rating.round}"
    end
    puts "=" * 60
  end

  desc "Recalculate ELO ratings without confirmation prompt"
  task recalculate_force: :environment do
    puts "=" * 60
    puts "ELO Rating Recalculator (Force Mode)"
    puts "=" * 60
    puts

    match_count = Match.count
    puts "Matches to process: #{match_count}"

    if match_count.zero?
      puts "No matches to process."
      next
    end

    puts "Resetting ratings and recalculating..."
    puts

    recalculator = EloRecalculator.new
    recalculator.call

    puts "Matches processed: #{recalculator.matches_processed}"

    if recalculator.errors.any?
      puts "Errors: #{recalculator.errors.count}"
      recalculator.errors.first(5).each { |e| puts "  - #{e}" }
    end

    puts
    puts "Top 5 Players by ELO:"
    Player.order(elo_rating: :desc).limit(5).each_with_index do |player, i|
      puts "#{i + 1}. #{player.nickname}: #{player.elo_rating.round}"
    end
    puts "=" * 60
  end
end
