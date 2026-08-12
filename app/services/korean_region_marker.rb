# Marks players as region "KR" when their name contains Korean Hangul
# characters, or when they have written Hangul in chat in any replay.
# Never overwrites an already-set region.
class KoreanRegionMarker
  HANGUL = /\p{Hangul}/
  REGION = "KR"

  # Full scan: all players by name, then all replays by chat
  def call
    marked = 0
    Player.where(region: [ nil, "" ]).find_each do |player|
      marked += 1 if mark_by_name(player)
    end
    Wc3statsReplay.find_each do |replay|
      marked += mark_from_replay(replay)
    end
    marked
  end

  # Mark a single player if any of their names contain Hangul
  def mark_by_name(player)
    names = [
      player.battletag,
      player.nickname,
      player.alternative_name,
      *(player.alternative_battletags || [])
    ].compact

    return false unless names.any? { |name| name.match?(HANGUL) }
    mark(player)
  end

  # Mark players who wrote Hangul in this replay's chat. Returns count marked.
  def mark_from_replay(replay)
    replay.hangul_chatter_battletags.count do |battletag|
      player = Player.find_by_any_battletag(battletag)
      player ? mark(player) : false
    end
  end

  private

  # Returns true if the player was newly marked
  def mark(player)
    return false if player.region.present?
    player.update_column(:region, REGION)
    true
  end
end
