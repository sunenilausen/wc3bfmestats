class AddAlternativeNameToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :alternative_name, :string
  end
end
