json.extract! player, :id, :battletag, :nickname, :battlenet_name, :elo_rating, :region, :battlenet_number, :created_at, :updated_at
json.url player_url(player, format: :json)
