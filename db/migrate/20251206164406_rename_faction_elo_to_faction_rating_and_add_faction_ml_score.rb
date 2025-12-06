class RenameFactionEloToFactionRatingAndAddFactionMlScore < ActiveRecord::Migration[8.1]
  def change
    rename_column :player_faction_stats, :faction_elo, :faction_rating
    add_column :player_faction_stats, :faction_score, :decimal
  end
end
