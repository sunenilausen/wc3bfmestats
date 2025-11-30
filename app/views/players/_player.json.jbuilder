json.extract! player, :id, :battletag, :nickname, :battlenet_name, :custom_rating, :ml_score, :region, :battlenet_number, :created_at, :updated_at
json.url player_url(player, format: :json)
