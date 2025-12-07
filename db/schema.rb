# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_12_07_192324) do
  create_table "ahoy_events", force: :cascade do |t|
    t.string "name"
    t.text "properties"
    t.datetime "time"
    t.integer "user_id"
    t.integer "visit_id"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "app_version"
    t.string "browser"
    t.string "city"
    t.string "country"
    t.string "device_type"
    t.string "ip"
    t.text "landing_page"
    t.float "latitude"
    t.float "longitude"
    t.string "os"
    t.string "os_version"
    t.string "platform"
    t.text "referrer"
    t.string "referring_domain"
    t.string "region"
    t.datetime "started_at"
    t.text "user_agent"
    t.integer "user_id"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.string "utm_term"
    t.string "visit_token"
    t.string "visitor_token"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "appearances", force: :cascade do |t|
    t.integer "bases_lost"
    t.integer "bases_total"
    t.float "castle_raze_pct"
    t.integer "castles_razed"
    t.integer "contribution_bonus"
    t.integer "contribution_rank"
    t.datetime "created_at", null: false
    t.integer "custom_rating"
    t.integer "custom_rating_change"
    t.integer "elo_rating"
    t.integer "elo_rating_change"
    t.integer "faction_id", null: false
    t.float "glicko2_rating"
    t.float "glicko2_rating_change"
    t.float "glicko2_rating_deviation"
    t.float "heal_pct"
    t.float "hero_kill_pct"
    t.integer "hero_kills"
    t.integer "heroes_lost"
    t.integer "heroes_total"
    t.boolean "ignore_hero_kills", default: false, null: false
    t.boolean "ignore_unit_kills", default: false, null: false
    t.boolean "is_mvp", default: false
    t.integer "match_id", null: false
    t.float "performance_score"
    t.integer "player_id", null: false
    t.integer "self_heal"
    t.integer "team_heal"
    t.float "team_heal_pct"
    t.boolean "top_hero_kills", default: false
    t.boolean "top_unit_kills", default: false
    t.integer "total_heal"
    t.float "unit_kill_pct"
    t.integer "unit_kills"
    t.datetime "updated_at", null: false
    t.index ["faction_id"], name: "index_appearances_on_faction_id"
    t.index ["match_id"], name: "index_appearances_on_match_id"
    t.index ["player_id"], name: "index_appearances_on_player_id"
  end

  create_table "factions", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.boolean "good"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "lobbies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "session_token"
    t.datetime "updated_at", null: false
  end

  create_table "lobby_observers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lobby_id", null: false
    t.integer "player_id", null: false
    t.datetime "updated_at", null: false
    t.index ["lobby_id"], name: "index_lobby_observers_on_lobby_id"
    t.index ["player_id"], name: "index_lobby_observers_on_player_id"
  end

  create_table "lobby_players", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "faction_id", null: false
    t.boolean "is_new_player", default: false
    t.integer "lobby_id", null: false
    t.integer "player_id"
    t.datetime "updated_at", null: false
    t.index ["faction_id"], name: "index_lobby_players_on_faction_id"
    t.index ["lobby_id"], name: "index_lobby_players_on_lobby_id"
    t.index ["player_id"], name: "index_lobby_players_on_player_id"
  end

  create_table "matches", force: :cascade do |t|
    t.integer "build_version"
    t.datetime "created_at", null: false
    t.boolean "good_victory"
    t.boolean "ignored", default: false, null: false
    t.integer "major_version"
    t.string "map_version"
    t.integer "row_order"
    t.integer "seconds"
    t.datetime "updated_at", null: false
    t.datetime "uploaded_at"
    t.integer "wc3stats_replay_id"
    t.index ["major_version", "build_version", "row_order", "map_version", "uploaded_at", "wc3stats_replay_id"], name: "index_matches_on_ordering"
    t.index ["wc3stats_replay_id"], name: "index_matches_on_wc3stats_replay_id"
  end

  create_table "player_faction_stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "faction_id", null: false
    t.decimal "faction_rating"
    t.decimal "faction_score"
    t.integer "games_played", default: 0, null: false
    t.float "performance_score", default: 0.0, null: false
    t.integer "player_id", null: false
    t.integer "rank"
    t.datetime "updated_at", null: false
    t.integer "wins", default: 0, null: false
    t.index ["faction_id", "performance_score"], name: "index_player_faction_stats_on_faction_id_and_performance_score"
    t.index ["faction_id", "rank"], name: "index_player_faction_stats_on_faction_id_and_rank"
    t.index ["faction_id"], name: "index_player_faction_stats_on_faction_id"
    t.index ["player_id", "faction_id"], name: "index_player_faction_stats_on_player_id_and_faction_id", unique: true
    t.index ["player_id"], name: "index_player_faction_stats_on_player_id"
  end

  create_table "players", force: :cascade do |t|
    t.json "alternative_battletags", default: []
    t.string "alternative_name"
    t.string "battlenet_name"
    t.integer "battlenet_number"
    t.string "battletag"
    t.datetime "created_at", null: false
    t.float "custom_rating"
    t.integer "custom_rating_bonus_wins"
    t.integer "custom_rating_games_played"
    t.boolean "custom_rating_reached_2000"
    t.float "custom_rating_seed"
    t.float "elo_rating"
    t.float "elo_rating_seed"
    t.float "glicko2_rating", default: 1500.0
    t.float "glicko2_rating_deviation", default: 350.0
    t.float "glicko2_rating_seed"
    t.float "glicko2_volatility", default: 0.06
    t.float "ml_score", default: 50.0
    t.string "nickname"
    t.string "region"
    t.datetime "updated_at", null: false
  end

  create_table "prediction_weights", force: :cascade do |t|
    t.float "accuracy", default: 0.0
    t.float "base_uptime_weight", default: 0.0
    t.float "bias", default: 0.0
    t.float "castle_raze_contribution_weight", default: 0.02
    t.datetime "created_at", null: false
    t.float "elo_weight", default: 1.0
    t.float "enemy_elo_diff_weight", default: 0.0
    t.float "games_played_weight", default: 0.0
    t.integer "games_trained_on", default: 0
    t.float "hero_kd_weight", default: 0.0
    t.float "hero_kill_contribution_weight", default: 0.0
    t.float "hero_uptime_weight", default: 0.0
    t.datetime "last_trained_at"
    t.float "team_heal_contribution_weight", default: 0.0
    t.float "unit_kill_contribution_weight", default: 0.0
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "unknown"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "wc3stats_replays", force: :cascade do |t|
    t.json "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "wc3stats_replay_id"
  end

  add_foreign_key "appearances", "factions"
  add_foreign_key "appearances", "matches"
  add_foreign_key "appearances", "players"
  add_foreign_key "lobby_observers", "lobbies"
  add_foreign_key "lobby_observers", "players"
  add_foreign_key "lobby_players", "factions"
  add_foreign_key "lobby_players", "lobbies"
  add_foreign_key "lobby_players", "players"
  add_foreign_key "matches", "wc3stats_replays"
  add_foreign_key "player_faction_stats", "factions"
  add_foreign_key "player_faction_stats", "players"
end
