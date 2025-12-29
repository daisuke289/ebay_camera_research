# frozen_string_literal: true

require_relative 'models/product'
require_relative 'models/snapshot'

# 履歴データの分析ロジック
class HistoryAnalyzer
  # トレンド判定の閾値
  TREND_THRESHOLDS = {
    rising: 0.1,    # 10%以上上昇で上昇トレンド
    falling: -0.1   # 10%以上下降で下降トレンド
  }.freeze

  # トレンド分析を実行
  # @param product [Product] 対象商品
  # @param days [Integer] 分析期間（日数）
  # @return [Hash] 分析結果
  def self.analyze_trend(product, days: 30)
    snapshots = product.snapshots_in_days(days)

    return { error: 'データ不足', message: '履歴データがありません' } if snapshots.empty?

    oldest = snapshots.last  # 一番古いデータ（降順なので最後）
    newest = snapshots.first # 一番新しいデータ

    # バランスの変動を計算
    balance_change = calculate_percentage_change(oldest.balance, newest.balance)
    price_change = calculate_percentage_change(oldest.avg_price_usd, newest.avg_price_usd)

    # トレンド判定
    trend = determine_trend(balance_change)

    {
      product_name: product.product_name,
      period_days: days,
      data_points: snapshots.length,
      balance: {
        oldest: oldest.balance&.round(2),
        newest: newest.balance&.round(2),
        change_percent: balance_change
      },
      price: {
        oldest: oldest.avg_price_usd&.round(2),
        newest: newest.avg_price_usd&.round(2),
        change_percent: price_change
      },
      trend: trend,
      snapshots: snapshots.map { |s| format_snapshot(s) },
      advice: generate_advice(trend, balance_change)
    }
  end

  # 上昇トレンドの商品を取得
  # @param days [Integer] 分析期間
  # @param limit [Integer] 取得件数
  # @return [Array<Hash>]
  def self.rising_products(days: 30, limit: 20)
    results = []

    Product.each do |product|
      analysis = analyze_trend(product, days: days)
      next if analysis[:error]
      next unless analysis[:trend] == :rising

      results << {
        product: product,
        balance_change: analysis[:balance][:change_percent],
        current_balance: analysis[:balance][:newest]
      }
    end

    results.sort_by { |r| -r[:balance_change] }.first(limit)
  end

  # 価格変動レポートを生成
  # @param days [Integer] 分析期間
  # @param threshold [Float] 変動率の閾値（例: 0.1 = 10%）
  # @return [Hash] 上昇/下落商品のリスト
  def self.price_change_report(days: 7, threshold: 0.1)
    changes = Snapshot.with_significant_price_changes(threshold: threshold, days: days)

    {
      period_days: days,
      threshold_percent: (threshold * 100).round(0),
      rising: changes.select { |c| c[:direction] == :up },
      falling: changes.select { |c| c[:direction] == :down },
      total_count: changes.length
    }
  end

  # コンソール用のトレンド可視化を生成
  # @param product [Product] 対象商品
  # @param days [Integer] 分析期間
  # @return [String] 可視化文字列
  def self.visualize_trend(product, days: 30)
    analysis = analyze_trend(product, days: days)

    return analysis[:message] if analysis[:error]

    lines = []
    lines << '=' * 70
    lines << "📈 トレンド分析: #{analysis[:product_name]}"
    lines << '=' * 70
    lines << ''
    lines << "📊 バランス推移（過去#{days}日）"

    # スナップショットを時系列で表示（古い順に並べ替え）
    snapshots = analysis[:snapshots].reverse
    max_balance = snapshots.map { |s| s[:balance] || 0 }.max
    max_balance = 1.0 if max_balance.zero?

    previous_balance = nil
    snapshots.each do |snapshot|
      balance = snapshot[:balance] || 0
      bar_length = (balance / max_balance * 20).round
      bar = '█' * bar_length + '░' * (20 - bar_length)

      change_str = ''
      if previous_balance && previous_balance.positive?
        change = ((balance - previous_balance) / previous_balance * 100).round(1)
        change_str = change.positive? ? "  ↑ +#{change}%" : "  ↓ #{change}%"
      end
      previous_balance = balance

      lines << format('   %s: %.1f  %s%s', snapshot[:date], balance, bar, change_str)
    end

    lines << ''
    lines << "🎯 判定: #{trend_label(analysis[:trend])}（過去#{days}日で #{format_change(analysis[:balance][:change_percent])}）"
    lines << "💡 アドバイス: #{analysis[:advice]}"
    lines << '=' * 70

    lines.join("\n")
  end

  # 価格変動レポートの可視化
  # @param days [Integer] 分析期間
  # @param threshold [Float] 変動率の閾値
  # @return [String] 可視化文字列
  def self.visualize_price_changes(days: 7, threshold: 0.1)
    report = price_change_report(days: days, threshold: threshold)

    lines = []
    lines << '=' * 70
    lines << "📉 価格変動レポート（過去#{days}日で#{report[:threshold_percent]}%以上変動）"
    lines << '=' * 70

    if report[:falling].any?
      lines << ''
      lines << '下落:'
      report[:falling].each do |item|
        lines << format('  %-20s $%.0f → $%.0f (%+.1f%%)  ⚠️ 相場下落',
                        truncate(item[:product].product_name, 20),
                        item[:old_price],
                        item[:new_price],
                        item[:change_percent])
      end
    end

    if report[:rising].any?
      lines << ''
      lines << '上昇:'
      report[:rising].each do |item|
        lines << format('  %-20s $%.0f → $%.0f (%+.1f%%) 📈 相場上昇',
                        truncate(item[:product].product_name, 20),
                        item[:old_price],
                        item[:new_price],
                        item[:change_percent])
      end
    end

    if report[:total_count].zero?
      lines << ''
      lines << "  該当する商品はありません"
    end

    lines << '=' * 70
    lines.join("\n")
  end

  class << self
    private

    # 変動率を計算
    def calculate_percentage_change(old_value, new_value)
      return nil unless old_value && new_value && old_value.positive?

      ((new_value - old_value) / old_value * 100).round(1)
    end

    # トレンドを判定
    def determine_trend(change_percent)
      return :unknown unless change_percent

      if change_percent >= TREND_THRESHOLDS[:rising] * 100
        :rising
      elsif change_percent <= TREND_THRESHOLDS[:falling] * 100
        :falling
      else
        :stable
      end
    end

    # スナップショットをフォーマット
    def format_snapshot(snapshot)
      {
        date: snapshot.recorded_at.strftime('%m/%d'),
        balance: snapshot.balance,
        active_count: snapshot.active_count,
        sold_count: snapshot.sold_count,
        avg_price_usd: snapshot.avg_price_usd
      }
    end

    # アドバイスを生成
    def generate_advice(trend, change_percent)
      case trend
      when :rising
        '需要急増中。仕入れ検討推奨。'
      when :falling
        '需要減少傾向。様子見を推奨。'
      when :stable
        '安定した需要。継続監視を推奨。'
      else
        'データ不足のため判定不能。'
      end
    end

    # トレンドのラベル
    def trend_label(trend)
      case trend
      when :rising  then '上昇トレンド'
      when :falling then '下降トレンド'
      when :stable  then '横ばい'
      else '判定不能'
      end
    end

    # 変動率のフォーマット
    def format_change(change)
      return 'N/A' unless change

      change.positive? ? "+#{change}%" : "#{change}%"
    end

    # 文字列の切り詰め
    def truncate(str, length)
      return str if str.length <= length

      str[0, length - 3] + '...'
    end
  end
end
