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

ActiveRecord::Schema[8.1].define(version: 2026_07_27_060000) do
  create_table "audit_logs", force: :cascade do |t|
    t.string "action"
    t.datetime "created_at", null: false
    t.text "detail"
    t.string "ip"
    t.datetime "updated_at", null: false
  end

  create_table "chat_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kimi_session_id"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "messages", force: :cascade do |t|
    t.integer "chat_session_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.string "role"
    t.text "sources"
    t.datetime "updated_at", null: false
    t.index ["chat_session_id"], name: "index_messages_on_chat_session_id"
  end

  add_foreign_key "messages", "chat_sessions"
end
