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

def export_players_csv
  CSV.generate do |csv|
    csv << [ "nickname", "elo_rating" ]
    Player.find_each do |player|
      csv << [ player.nickname, player.elo_rating ]
    end
  end
end

# Example usage:
# puts export_players_csv
