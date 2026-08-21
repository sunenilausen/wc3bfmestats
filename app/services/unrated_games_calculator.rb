# Counts the games a player took part in that the rating system had to throw away.
#
# A replay whose map never reported a result leaves every player with no
# isWinner flag, so Wc3stats::MatchBuilder treats them all as observers and the
# match is built with no appearances at all. Those games are unusable for
# rating - there is no outcome, and almost none of them carry stats - but the
# players in them are real, and several have dozens of games that leave no trace
# anywhere on the site. Without this they look like complete newcomers.
#
# Counted for display only. Nothing here feeds a rating, a K-factor or the
# unproven dock: an unrated game is evidence that someone has played, not
# evidence of how well.
class UnratedGamesCalculator
  MIN_GAME_LENGTH = 120

  attr_reader :players_updated

  def initialize
    @players_updated = 0
  end

  def call
    counts = Hash.new(0)

    dropped_replays.each do |replay|
      slot_battletags(replay).each do |battletag|
        player_id = lookup[battletag.downcase]
        counts[player_id] += 1 if player_id
      end
    end

    apply(counts)
    self
  end

  private

  # Matches the builder produced no appearances for, which is what happens when
  # no player has a win/loss status. Test maps and lobby-length games excluded.
  def dropped_replays
    match_ids = Match.where.missing(:appearances).pluck(:id)
    Wc3statsReplay.joins(:match).where(matches: { id: match_ids }).find_each(batch_size: 200).reject do |replay|
      replay.game_length.to_i < MIN_GAME_LENGTH || replay.test_map?
    end
  end

  def slot_battletags(replay)
    replay.players.filter_map do |player|
      slot = player["slot"]
      next unless slot.present? && slot.between?(0, 9)

      tag = replay.fix_encoding(player["name"].to_s)
      tag.presence
    end
  end

  # battletag (downcased) => player id, covering primary and alternative tags so
  # a merged player is credited once rather than spawning a second total.
  def lookup
    @lookup ||= begin
      index = {}
      Player.pluck(:id, :battletag, :alternative_battletags).each do |id, battletag, alternatives|
        index[battletag.downcase] = id if battletag.present?
        Array(alternatives).each { |alt| index[alt.downcase] ||= id if alt.present? }
      end
      index
    end
  end

  def apply(counts)
    Player.where.not(unrated_games: 0).where.not(id: counts.keys).update_all(unrated_games: 0)

    counts.each do |player_id, count|
      updated = Player.where(id: player_id).where.not(unrated_games: count).update_all(unrated_games: count)
      @players_updated += updated
    end
  end
end
