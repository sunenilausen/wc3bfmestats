class AddCachedEventStatsToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :hero_kd_ratio, :float
    add_column :players, :hero_uptime, :float
    add_column :players, :base_uptime, :float
  end
end
