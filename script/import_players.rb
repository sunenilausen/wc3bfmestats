example_players_csv = <<~CSVCSV
nickname,elo_rating
KaptajnSnaps,1500
PlayerTwo,1600
PlayerThree,1400
CSVCSV

require 'csv'
CSV.parse(example_players_csv, headers: true) do |row|
  Player.create!(
    nickname: row['nickname'],
    elo_rating: row['elo_rating'].to_i || 1500,
    elo_rating_seed: row['elo_rating'].to_i || 1500
  )
end


require 'csv'
CSV.generate do |csv|
  csv << [ "nickname", "elo_rating", "appearances_count", "last appearance", "wins", "losses" ]
  Player.find_each do |player|
    csv << [ player.nickname, player.elo_rating, player.appearances.count, player.matches.by_played_at(:desc).first.played_at_formatted, player.wins, player.losses ]
  end
end

# Example usage:
# puts export_players_csv
