namespace :players do
  desc "Generate players from imported WC3Stats replays"
  task generate: :environment do
    puts "=" * 60
    puts "Generating Players from WC3Stats Replays"
    puts "=" * 60
    
    replays = Wc3statsReplay.all
    
    if replays.empty?
      puts "No replays found. Import replays first using: rails wc3stats:import"
      exit
    end
    
    puts "Processing #{replays.count} replays..."
    puts
    
    all_player_names = Set.new
    player_stats = {}
    
    # Collect all unique player names and their stats
    replays.each do |replay|
      replay.players.each do |player_data|
        name = player_data["name"]
        next if name.blank?
        
        all_player_names << name
        
        # Initialize stats for this player if needed
        player_stats[name] ||= {
          games_played: 0,
          wins: 0,
          losses: 0,
          total_unit_kills: 0,
          total_hero_kills: 0
        }
        
        # Update stats
        player_stats[name][:games_played] += 1
        if player_data["isWinner"]
          player_stats[name][:wins] += 1
        else
          player_stats[name][:losses] += 1
        end
        player_stats[name][:total_unit_kills] += player_data.dig("variables", "unitKills") || 0
        player_stats[name][:total_hero_kills] += player_data.dig("variables", "heroKills") || 0
      end
    end
    
    puts "Found #{all_player_names.count} unique players across all replays"
    puts
    
    # Check existing players
    existing_players = Player.where(battletag: all_player_names.to_a)
    existing_battletags = existing_players.pluck(:battletag)
    new_battletags = all_player_names - existing_battletags
    
    puts "📊 Status:"
    puts "  Total unique players: #{all_player_names.count}"
    puts "  Already in database: #{existing_battletags.count}"
    puts "  New players to create: #{new_battletags.count}"
    puts
    
    if new_battletags.empty?
      puts "✓ All players already exist in database!"
    else
      puts "Creating #{new_battletags.count} new players..."
      puts
      
      created_count = 0
      failed_count = 0
      
      new_battletags.each do |battletag|
        # Extract nickname from battletag (remove #numbers if present)
        nickname = battletag.split('#').first
        
        player = Player.new(
          battletag: battletag,
          nickname: nickname,
          elo_rating: 1500,
          elo_rating_seed: 1500
        )
        
        if player.save
          created_count += 1
          stats = player_stats[battletag]
          win_rate = stats[:games_played] > 0 ? (stats[:wins].to_f / stats[:games_played] * 100).round(1) : 0
          
          puts "✓ Created: #{battletag}"
          puts "  Games: #{stats[:games_played]}, W/L: #{stats[:wins]}/#{stats[:losses]} (#{win_rate}%)"
          puts "  Kills: #{stats[:total_unit_kills]} units, #{stats[:total_hero_kills]} heroes"
        else
          failed_count += 1
          puts "✗ Failed to create: #{battletag}"
          puts "  Error: #{player.errors.full_messages.join(', ')}"
        end
        puts
      end
      
      puts "=" * 60
      puts "Summary"
      puts "=" * 60
      puts "✓ Successfully created: #{created_count} players"
      puts "✗ Failed: #{failed_count}" if failed_count > 0
    end
    
    puts
    puts "Total players in database: #{Player.count}"
    puts
    
    # Show top players by games played
    puts "Top 10 Players by Games Played:"
    puts "-" * 40
    top_players = player_stats.sort_by { |_name, stats| -stats[:games_played] }.first(10)
    top_players.each_with_index do |(name, stats), index|
      win_rate = stats[:games_played] > 0 ? (stats[:wins].to_f / stats[:games_played] * 100).round(1) : 0
      avg_kills = stats[:games_played] > 0 ? (stats[:total_unit_kills].to_f / stats[:games_played]).round(1) : 0
      puts "#{index + 1}. #{name}"
      puts "   Games: #{stats[:games_played]}, Win rate: #{win_rate}%"
      puts "   Avg unit kills/game: #{avg_kills}"
    end
    puts "=" * 60
  end
end