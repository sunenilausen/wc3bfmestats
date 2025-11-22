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

ActiveRecord::Schema[8.1].define(version: 2025_11_22_162345) do
  create_table "appearances", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "elo_rating"
    t.integer "elo_rating_change"
    t.integer "faction_id", null: false
    t.integer "hero_kills"
    t.integer "match_id", null: false
    t.integer "player_id", null: false
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

  create_table "matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "good_victory"
    t.datetime "played_at"
    t.integer "seconds"
    t.datetime "updated_at", null: false
    t.integer "wc3stats_replay_id"
    t.index ["wc3stats_replay_id"], name: "index_matches_on_wc3stats_replay_id"
  end

  create_table "players", force: :cascade do |t|
    t.string "battlenet_name"
    t.integer "battlenet_number"
    t.string "battletag"
    t.datetime "created_at", null: false
    t.float "elo_rating"
    t.float "elo_rating_seed"
    t.string "nickname"
    t.string "region"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role"
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
  add_foreign_key "matches", "wc3stats_replays"
end
