example_players_csv = <<~CSVCSV
nickname,custom_rating
KaptajnSnaps,1300
PlayerTwo,1400
PlayerThree,1200
CSVCSV

require 'csv'
CSV.parse(example_players_csv, headers: true) do |row|
  Player.create!(
    nickname: row['nickname'],
    custom_rating: row['custom_rating'].to_i || 1300,
    ml_score: 35.0
  )
end


require 'csv'
CSV.generate do |csv|
  csv << [ "nickname", "custom_rating", "ml_score", "appearances_count", "last appearance", "wins", "losses" ]
  Player.find_each do |player|
    csv << [ player.nickname, player.custom_rating, player.ml_score, player.appearances.count, player.matches.by_uploaded_at(:desc).first.uploaded_at_formatted, player.wins, player.losses ]
  end
end

# Example usage:
# puts export_players_csv
