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

ActiveRecord::Schema[7.0].define(version: 2022_02_09_143347) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "timescaledb"

  create_table "games", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "plays", id: false, force: :cascade do |t|
    t.bigint "game_id", null: false
    t.integer "score"
    t.decimal "total_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "plays_created_at_idx", order: :desc
    t.index ["game_id"], name: "index_plays_on_game_id"
  end

  create_hypertable "plays", time_column: "created_at", chunk_time_interval: "1 minute", compress_segmentby: "game_id", compress_orderby: "created_at ASC", compression_interval: "P7D"

  create_continuous_aggregate("score_per_hours", <<-SQL)
    SELECT plays.game_id,
      time_bucket('PT1H'::interval, plays.created_at) AS bucket,
      avg(plays.score) AS avg,
      max(plays.score) AS max,
      min(plays.score) AS min
     FROM plays
    GROUP BY plays.game_id, (time_bucket('PT1H'::interval, plays.created_at))
  SQL

end
