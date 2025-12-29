# frozen_string_literal: true

require_relative '../../db/database'

# 履歴スナップショットモデル
# 各時点でのeBayデータを記録
class Snapshot < Sequel::Model
  many_to_one :product

  # 取得データからスナップショットを作成
  # @param product [Product] 対象商品
  # @param data [Hash] 取得データ
  # @return [Snapshot]
  def self.record(product, data)
    create(
      product_id: product.id,
      active_count: data[:active_count],
      sold_count: data[:sold_count],
      balance: data[:balance],
      avg_price_usd: data[:avg_price_usd],
      avg_price_jpy: data[:avg_price_jpy],
      min_price_usd: data[:min_price_usd],
      max_price_usd: data[:max_price_usd],
      recorded_at: Time.now
    )
  end

  # 前回との差分を計算
  # @param previous [Snapshot] 前回のスナップショット
  # @return [Hash] 差分データ
  def diff_from(previous)
    return nil unless previous

    {
      balance_change: calculate_change(balance, previous.balance),
      price_change: calculate_change(avg_price_usd, previous.avg_price_usd),
      active_count_change: (active_count || 0) - (previous.active_count || 0),
      sold_count_change: (sold_count || 0) - (previous.sold_count || 0)
    }
  end

  # 指定日以降のスナップショットを取得
  # @param since [Time] 開始日時
  # @return [Array<Snapshot>]
  def self.since(since)
    where { recorded_at >= since }.order(:recorded_at).all
  end

  # 価格変動が大きい商品のスナップショットを取得
  # @param threshold [Float] 変動率の閾値（例: 0.1 = 10%）
  # @param days [Integer] 過去何日間を対象とするか
  # @return [Array<Hash>] 変動情報のリスト
  def self.with_significant_price_changes(threshold: 0.1, days: 7)
    since = Time.now - (days * 24 * 60 * 60)

    # 一括でスナップショットを取得し、product_idでグループ化（N+1問題を回避）
    snapshots_by_product = Snapshot
                           .where { recorded_at >= since }
                           .order(:product_id, :recorded_at)
                           .eager(:product)
                           .all
                           .group_by(&:product_id)

    results = []

    snapshots_by_product.each do |_product_id, snapshots|
      next if snapshots.length < 2

      oldest = snapshots.first
      newest = snapshots.last

      next unless oldest.avg_price_usd && newest.avg_price_usd && oldest.avg_price_usd.positive?

      change = (newest.avg_price_usd - oldest.avg_price_usd) / oldest.avg_price_usd

      next unless change.abs >= threshold

      results << {
        product: oldest.product,
        old_price: oldest.avg_price_usd,
        new_price: newest.avg_price_usd,
        change_percent: (change * 100).round(1),
        direction: change.positive? ? :up : :down
      }
    end

    results.sort_by { |r| -r[:change_percent].abs }
  end

  private

  # 変動率を計算
  # @param current [Float, nil]
  # @param previous [Float, nil]
  # @return [Float, nil] 変動率（%）
  def calculate_change(current, previous)
    return nil unless current && previous && previous.positive?

    ((current - previous) / previous * 100).round(1)
  end
end
