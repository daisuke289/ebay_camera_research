# frozen_string_literal: true

# 売れ行き率（バランス）を計算するクラス
class BalanceCalculator
  # バランスのランク定義
  RANKS = {
    excellent: { min: 2.0, label: '超優良', description: '需要 > 供給、即仕入れ候補' },
    good: { min: 1.0, label: '良好', description: '需要と供給が均衡、仕入れ検討' },
    fair: { min: 0.5, label: '普通', description: '供給がやや多い、様子見' },
    poor: { min: 0.0, label: '要注意', description: '供給過多、避ける' }
  }.freeze

  class << self
    # バランス（売れ行き率）を計算
    #
    # @param sold_count [Integer] 落札数（過去90日）
    # @param active_count [Integer] 出品数
    # @return [Float, nil] バランス値（出品数が0の場合はnil）
    def calculate(sold_count:, active_count:)
      return nil if active_count.nil? || active_count.zero?
      return 0.0 if sold_count.nil? || sold_count.zero?

      (sold_count.to_f / active_count).round(2)
    end

    # バランス値からランクを判定
    #
    # @param balance [Float] バランス値
    # @return [Symbol] ランク（:excellent, :good, :fair, :poor）
    def rank(balance)
      return :poor if balance.nil? || balance < RANKS[:fair][:min]
      return :excellent if balance >= RANKS[:excellent][:min]
      return :good if balance >= RANKS[:good][:min]

      :fair
    end

    # バランス値からランク情報を取得
    #
    # @param balance [Float] バランス値
    # @return [Hash] ランク情報（:label, :description）
    def rank_info(balance)
      rank_key = rank(balance)
      RANKS[rank_key]
    end

    # ランクラベルを取得
    #
    # @param balance [Float] バランス値
    # @return [String] ランクラベル
    def rank_label(balance)
      rank_info(balance)[:label]
    end

    # 複数商品のバランスを一括計算
    #
    # @param products [Array<Hash>] 商品データの配列
    #   - :sold_count [Integer] 落札数
    #   - :active_count [Integer] 出品数
    # @return [Array<Hash>] バランス情報を追加した配列
    def calculate_all(products)
      products.map do |product|
        balance = calculate(
          sold_count: product[:sold_count],
          active_count: product[:active_count]
        )

        product.merge(
          balance: balance,
          rank: rank(balance),
          rank_label: rank_label(balance)
        )
      end
    end

    # バランス上位の商品を抽出
    #
    # @param products [Array<Hash>] 商品データの配列
    # @param limit [Integer] 取得件数
    # @return [Array<Hash>] バランス上位の商品
    def top_products(products, limit: 100)
      products_with_balance = calculate_all(products)
      
      products_with_balance
        .select { |p| p[:balance] && p[:balance].positive? }
        .sort_by { |p| -p[:balance] }
        .first(limit)
    end

    # 仕入れ推奨商品を抽出（バランス1.0以上）
    #
    # @param products [Array<Hash>] 商品データの配列
    # @return [Array<Hash>] 仕入れ推奨商品
    def recommended_products(products)
      products_with_balance = calculate_all(products)
      
      products_with_balance
        .select { |p| p[:balance] && p[:balance] >= RANKS[:good][:min] }
        .sort_by { |p| -p[:balance] }
    end

    # カテゴリ別の統計を計算
    #
    # @param products [Array<Hash>] 商品データの配列
    # @return [Hash] カテゴリ別統計
    def stats_by_category(products)
      products_with_balance = calculate_all(products)
      
      products_with_balance
        .group_by { |p| p[:category] }
        .transform_values { |items| calculate_category_stats(items) }
    end

    # メーカー別の統計を計算
    #
    # @param products [Array<Hash>] 商品データの配列
    # @return [Hash] メーカー別統計
    def stats_by_maker(products)
      products_with_balance = calculate_all(products)
      
      products_with_balance
        .group_by { |p| p[:maker] }
        .transform_values { |items| calculate_category_stats(items) }
    end

    private

    # カテゴリ/メーカーの統計を計算
    def calculate_category_stats(items)
      balances = items.map { |i| i[:balance] }.compact
      
      return {} if balances.empty?

      {
        count: items.length,
        avg_balance: (balances.sum / balances.length).round(2),
        max_balance: balances.max,
        min_balance: balances.min,
        excellent_count: items.count { |i| rank(i[:balance]) == :excellent },
        good_count: items.count { |i| rank(i[:balance]) == :good },
        fair_count: items.count { |i| rank(i[:balance]) == :fair },
        poor_count: items.count { |i| rank(i[:balance]) == :poor }
      }
    end
  end
end
