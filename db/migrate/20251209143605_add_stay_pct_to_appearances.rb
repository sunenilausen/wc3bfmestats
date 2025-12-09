class AddStayPctToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :stay_pct, :float
  end
end
