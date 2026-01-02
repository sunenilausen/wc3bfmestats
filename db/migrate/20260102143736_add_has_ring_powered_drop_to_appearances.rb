class AddHasRingPoweredDropToAppearances < ActiveRecord::Migration[8.1]
  def change
    add_column :appearances, :has_ring_powered_drop, :boolean, default: false, null: false
  end
end
