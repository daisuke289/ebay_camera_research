# frozen_string_literal: true

Sequel.migration do
  change do
    # 商品マスタテーブル
    create_table(:products) do
      primary_key :id
      Integer :row_number, null: false, unique: true
      String :category
      String :maker
      String :product_name, null: false
      String :ebay_active_url, text: true
      String :ebay_sold_url, text: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :row_number
      index :maker
      index :category
    end

    # 履歴スナップショットテーブル
    create_table(:snapshots) do
      primary_key :id
      foreign_key :product_id, :products, null: false, on_delete: :cascade
      Integer :active_count
      Integer :sold_count
      Float :balance
      Float :avg_price_usd
      Integer :avg_price_jpy
      Float :min_price_usd
      Float :max_price_usd
      DateTime :recorded_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:product_id, :recorded_at]
      index :recorded_at
    end
  end
end
