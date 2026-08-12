class AddHostBattletagToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :host_battletag, :string
    add_index :matches, :host_battletag
  end
end
