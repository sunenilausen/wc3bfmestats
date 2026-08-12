class BackfillKoreanRegionFromNamesAndChat < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    marked = KoreanRegionMarker.new.call
    say "Marked #{marked} players as region KR"
  end

  def down
    # No-op: don't remove data on rollback
  end
end
