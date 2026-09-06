# Recomputes the fields that were derived from the recorded replay length for
# matches where one player idled in the game after it ended. See
# Wc3statsReplay#effective_length.
class BackfillContestedGameLength < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  MIN_GAME_LENGTH = 120

  def up
    fixed = 0

    Match.joins(:wc3stats_replay).includes(:wc3stats_replay, :appearances).find_each do |match|
      replay = match.wc3stats_replay
      next unless replay.idle_tail?

      contested = replay.effective_length
      match.update_columns(seconds: contested)

      replay.active_slot_players.each do |player_data|
        appearance = appearance_for(match, replay, player_data)
        next unless appearance

        appearance.update_columns(stay_pct: replay.stay_percent_for(player_data))
      end

      # The idle tail was hiding how short the game really was.
      match.update_columns(ignored: true) if contested && contested < MIN_GAME_LENGTH

      fixed += 1
    end

    say "Recomputed contested length for #{fixed} matches"
  end

  def down
    # No-op: don't remove data on rollback
  end

  private

  def appearance_for(match, replay, player_data)
    battletag = player_data["name"].to_s
    candidates = [ battletag, replay.send(:fix_encoding, battletag) ].compact.uniq

    match.appearances.detect do |a|
      player = a.player
      next false unless player
      candidates.include?(player.battletag) ||
        Array(player.try(:alternative_battletags)).intersect?(candidates)
    end
  end
end
