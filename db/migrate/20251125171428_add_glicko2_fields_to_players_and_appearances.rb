class AddGlicko2FieldsToPlayersAndAppearances < ActiveRecord::Migration[8.0]
  def change
    # Glicko-2 uses three values per player:
    # - rating (mu): skill estimate, default 1500 (same scale as ELO for familiarity)
    # - rating_deviation (phi): uncertainty, default 350 (high uncertainty for new players)
    # - volatility (sigma): expected fluctuation, default 0.06

    # Player current Glicko-2 ratings
    add_column :players, :glicko2_rating, :float, default: 1500.0
    add_column :players, :glicko2_rating_deviation, :float, default: 350.0
    add_column :players, :glicko2_volatility, :float, default: 0.06
    add_column :players, :glicko2_rating_seed, :float

    # Appearance Glicko-2 snapshot (rating at time of match and change)
    add_column :appearances, :glicko2_rating, :float
    add_column :appearances, :glicko2_rating_deviation, :float
    add_column :appearances, :glicko2_rating_change, :float
  end
end
