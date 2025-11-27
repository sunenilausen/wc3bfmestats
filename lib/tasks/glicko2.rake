namespace :glicko2 do
  desc "Recalculate Glicko-2 ratings for all matches chronologically"
  task recalculate: :environment do
    puts "=" * 60
    puts "Glicko-2 Rating Recalculator"
    puts "=" * 60
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

    recalculator = Glicko2Recalculator.new
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
    puts "Top 10 Players by Glicko-2:"
    puts "-" * 40
    Player.order(glicko2_rating: :desc).limit(10).each_with_index do |player, i|
      rd = player.glicko2_rating_deviation.round
      puts "#{i + 1}. #{player.nickname}: #{player.glicko2_rating.round} (RD: #{rd})"
    end
    puts "=" * 60
  end

  desc "Recalculate Glicko-2 ratings without confirmation prompt"
  task recalculate_force: :environment do
    puts "=" * 60
    puts "Glicko-2 Rating Recalculator (Force Mode)"
    puts "=" * 60
    puts

    match_count = Match.where(ignored: false).count
    puts "Matches to process: #{match_count}"

    if match_count.zero?
      puts "No matches to process."
      next
    end

    puts "Resetting ratings and recalculating..."
    puts

    recalculator = Glicko2Recalculator.new
    recalculator.call

    puts "Matches processed: #{recalculator.matches_processed}"

    if recalculator.errors.any?
      puts "Errors: #{recalculator.errors.count}"
      recalculator.errors.first(5).each { |e| puts "  - #{e}" }
    end

    puts
    puts "Top 5 Players by Glicko-2:"
    Player.order(glicko2_rating: :desc).limit(5).each_with_index do |player, i|
      rd = player.glicko2_rating_deviation.round
      puts "#{i + 1}. #{player.nickname}: #{player.glicko2_rating.round} (RD: #{rd})"
    end
    puts "=" * 60
  end

  desc "Show Glicko-2 leaderboard"
  task leaderboard: :environment do
    puts "=" * 60
    puts "Glicko-2 Leaderboard"
    puts "=" * 60
    puts
    puts "Top 20 Players (sorted by rating):"
    puts "-" * 55
    puts "#{'#'.ljust(3)} #{'Player'.ljust(20)} #{'Rating'.rjust(6)} #{'RD'.rjust(5)} #{'Games'.rjust(6)}"
    puts "-" * 55

    # Get appearance counts
    appearance_counts = Appearance.group(:player_id).count

    Player.order(glicko2_rating: :desc)
          .limit(20)
          .each_with_index do |player, i|
      games = appearance_counts[player.id] || 0
      puts "#{(i + 1).to_s.ljust(3)} #{player.nickname.truncate(20).ljust(20)} #{player.glicko2_rating.round.to_s.rjust(6)} #{player.glicko2_rating_deviation.round.to_s.rjust(5)} #{games.to_s.rjust(6)}"
    end
    puts "=" * 55
  end
end
