# Recent results per player, most recent first - the "form" strip you see in a
# football league table.
#
# Returns { player_id => ["W", "L", "W", ...] } with at most GAMES entries each.
class PlayerForm
  GAMES = 5

  WIN = "W"
  LOSS = "L"
  DRAW = "D"

  # Pass player_ids to limit the query, or nil for every player
  def self.recent(player_ids = nil, games: GAMES)
    rows(player_ids, games).each_with_object({}) do |row, form|
      (form[row["player_id"]] ||= []) << result_for(row)
    end
  end

  # How many of those recent games the player left early
  def self.recent_leaves(player_ids = nil, games: GAMES)
    rows(player_ids, games).each_with_object(Hash.new(0)) do |row, leaves|
      leaves[row["player_id"]] += 1 if truthy?(row["is_early_leaver"])
    end
  end

  # Two static statements rather than one with an OR switch: the OR stopped
  # SQLite using the index on the all-players scan and cost 8x. Neither embeds
  # a value - the ids and the game count are bound.
  def self.build_sql(player_filter)
    <<~SQL.squish
      SELECT player_id, good_victory, is_good, is_draw, is_early_leaver
      FROM (
        SELECT a.player_id AS player_id,
               m.good_victory AS good_victory,
               f.good AS is_good,
               m.is_draw AS is_draw,
               a.is_early_leaver AS is_early_leaver,
               ROW_NUMBER() OVER (
                 PARTITION BY a.player_id
                 ORDER BY m.played_at DESC, m.id DESC
               ) AS position
        FROM appearances a
        JOIN matches m ON m.id = a.match_id
        JOIN factions f ON f.id = a.faction_id
        WHERE m.ignored = 0 AND m.good_victory IS NOT NULL #{player_filter}
      ) ranked
      WHERE position <= :games
      ORDER BY player_id, position
    SQL
  end

  EVERY_PLAYER_SQL = build_sql("").freeze
  SELECTED_PLAYERS_SQL = build_sql("AND a.player_id IN (:player_ids)").freeze

  def self.rows(player_ids, games)
    binds = { games: games.to_i }

    if player_ids
      ids = Array(player_ids)
      return [] if ids.empty?
      template = SELECTED_PLAYERS_SQL
      binds[:player_ids] = ids
    else
      template = EVERY_PLAYER_SQL
    end

    ActiveRecord::Base.connection.select_all(ActiveRecord::Base.sanitize_sql_array([ template, binds ]))
  end

  def self.result_for(row)
    return DRAW if truthy?(row["is_draw"])

    truthy?(row["good_victory"]) == truthy?(row["is_good"]) ? WIN : LOSS
  end

  def self.truthy?(value)
    value == true || value == 1 || value == "t"
  end
end
