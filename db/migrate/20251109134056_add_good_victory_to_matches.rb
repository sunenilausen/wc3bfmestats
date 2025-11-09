class AddGoodVictoryToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :good_victory, :boolean
  end
end
