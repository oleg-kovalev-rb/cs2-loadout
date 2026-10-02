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

ActiveRecord::Schema[7.2].define(version: 2026_10_01_155638) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "inventory_value_logs", force: :cascade do |t|
    t.string "steam_id", null: false
    t.date "log_date", null: false
    t.integer "total_value_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["steam_id", "log_date"], name: "index_inventory_value_logs_on_steam_id_and_log_date", unique: true
  end

  create_table "items", force: :cascade do |t|
    t.string "market_hash_name", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "current_price_cents"
    t.integer "change_24h_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["market_hash_name"], name: "index_items_on_market_hash_name", unique: true
    t.index ["metadata"], name: "index_items_on_metadata", using: :gin
  end

  create_table "price_logs", force: :cascade do |t|
    t.bigint "item_id", null: false
    t.integer "lowest_price_cents", default: 0, null: false
    t.integer "median_price_cents", default: 0, null: false
    t.integer "volume", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id", "created_at"], name: "index_price_logs_on_item_id_and_created_at"
    t.index ["item_id"], name: "index_price_logs_on_item_id"
  end

  create_table "user_inventories", force: :cascade do |t|
    t.string "steam_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["steam_id"], name: "index_user_inventories_on_steam_id", unique: true
  end

  create_table "user_inventory_items", force: :cascade do |t|
    t.bigint "user_inventory_id", null: false
    t.bigint "item_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_inventory_id", "item_id"], name: "index_user_inventory_items_on_user_inventory_id_and_item_id", unique: true
  end

  add_foreign_key "price_logs", "items"
  add_foreign_key "user_inventory_items", "items"
  add_foreign_key "user_inventory_items", "user_inventories"
end
