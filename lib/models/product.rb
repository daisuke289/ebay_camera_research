# frozen_string_literal: true

require_relative '../../db/database'

# 商品マスタモデル
# スプレッドシートの商品情報を管理
class Product < Sequel::Model
  one_to_many :snapshots, order: Sequel.desc(:recorded_at)

  # 最新のスナップショットを取得
  # @return [Snapshot, nil]
  def latest_snapshot
    snapshots_dataset.first
  end

  # 指定期間のスナップショットを取得
  # @param days [Integer] 過去何日分を取得するか
  # @return [Array<Snapshot>]
  def snapshots_in_days(days)
    since = Time.now - (days * 24 * 60 * 60)
    snapshots_dataset.where { recorded_at >= since }.all
  end

  # スプレッドシートのデータから商品を作成または更新
  # @param sheet_data [Hash] スプレッドシートから読み込んだデータ
  # @return [Product]
  def self.sync_from_sheet(sheet_data)
    product = find(row_number: sheet_data[:row_number])

    if product
      # 既存レコードは更新
      product.update(
        category: sheet_data[:category],
        maker: sheet_data[:maker],
        product_name: sheet_data[:product_name],
        ebay_active_url: sheet_data[:ebay_active_url],
        ebay_sold_url: sheet_data[:ebay_sold_url],
        updated_at: Time.now
      )
    else
      # 新規レコードは作成
      product = create(
        row_number: sheet_data[:row_number],
        category: sheet_data[:category],
        maker: sheet_data[:maker],
        product_name: sheet_data[:product_name],
        ebay_active_url: sheet_data[:ebay_active_url],
        ebay_sold_url: sheet_data[:ebay_sold_url]
      )
    end

    product
  end

  # 商品名で検索（部分一致）
  # @param name [String] 検索キーワード
  # @return [Array<Product>]
  def self.search_by_name(name)
    where(Sequel.ilike(:product_name, "%#{name}%")).all
  end

  # メーカーで絞り込み
  # @param maker [String] メーカー名
  # @return [Array<Product>]
  def self.by_maker(maker)
    where(Sequel.ilike(:maker, maker)).all
  end
end
