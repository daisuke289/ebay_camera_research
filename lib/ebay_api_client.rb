# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'
require 'oj'
require 'logger'

# eBay API を操作するクライアントクラス
# Browse API と Finding API をサポート
class EbayApiClient
  # API エンドポイント
  BROWSE_API_URL = 'https://api.ebay.com/buy/browse/v1'
  FINDING_API_URL = 'https://svcs.ebay.com/services/search/FindingService/v1'

  # デフォルト設定
  DEFAULT_TIMEOUT = 30
  DEFAULT_RETRY_COUNT = 3
  DEFAULT_DELAY = 1

  # 過去90日（eBay APIの最大取得期間）
  SOLD_ITEMS_DAYS = 90

  attr_reader :logger

  # @param app_id [String] eBay Application ID
  # @param oauth_token [String] OAuth Token (Browse API用)
  # @param environment [String] 'sandbox' or 'production'
  # @param logger [Logger] ロガー
  def initialize(app_id:, oauth_token: nil, environment: 'production', logger: nil)
    @app_id = app_id
    @oauth_token = oauth_token
    @environment = environment
    @logger = logger || Logger.new($stdout)
    @delay = DEFAULT_DELAY
  end

  # 出品中の商品数を取得（Finding API）
  #
  # @param keyword [String] 検索キーワード
  # @param category_id [String] カテゴリID
  # @param condition_id [String] 商品状態ID
  # @param options [Hash] その他のオプション
  # @return [Integer] 出品数
  def get_active_listing_count(keyword:, category_id: nil, condition_id: nil, **options)
    response = find_items(
      operation: 'findItemsAdvanced',
      keyword: keyword,
      category_id: category_id,
      condition_id: condition_id,
      listing_type: options[:buy_it_now] ? 'FixedPrice' : nil,
      entries_per_page: 1  # カウントのみ取得
    )

    extract_total_count(response)
  rescue StandardError => e
    logger.error("Failed to get active listing count: #{e.message}")
    0
  end

  # 販売済み商品数を取得（Finding API）
  #
  # @param keyword [String] 検索キーワード
  # @param category_id [String] カテゴリID
  # @param condition_id [String] 商品状態ID
  # @param options [Hash] その他のオプション
  # @return [Integer] 落札数（過去90日）
  def get_sold_item_count(keyword:, category_id: nil, condition_id: nil, **options)
    response = find_items(
      operation: 'findCompletedItems',
      keyword: keyword,
      category_id: category_id,
      condition_id: condition_id,
      listing_type: options[:buy_it_now] ? 'FixedPrice' : nil,
      sold_items_only: true,
      entries_per_page: 1  # カウントのみ取得
    )

    extract_total_count(response)
  rescue StandardError => e
    logger.error("Failed to get sold item count: #{e.message}")
    0
  end

  # URLパラメータから出品数を取得
  #
  # @param url_params [Hash] EbayUrlParser.parse の結果
  # @return [Integer] 出品数
  def get_active_count_from_params(url_params)
    get_active_listing_count(
      keyword: url_params[:keyword],
      category_id: url_params[:category_id],
      condition_id: url_params[:condition_id],
      buy_it_now: url_params[:buy_it_now]
    )
  end

  # URLパラメータから落札数を取得
  #
  # @param url_params [Hash] EbayUrlParser.parse の結果
  # @return [Integer] 落札数
  def get_sold_count_from_params(url_params)
    get_sold_item_count(
      keyword: url_params[:keyword],
      category_id: url_params[:category_id],
      condition_id: url_params[:condition_id],
      buy_it_now: url_params[:buy_it_now]
    )
  end

  # 販売済み商品の価格情報を取得
  #
  # @param keyword [String] 検索キーワード
  # @param category_id [String] カテゴリID
  # @param limit [Integer] 取得件数
  # @return [Hash] 価格統計情報
  def get_sold_price_stats(keyword:, category_id: nil, limit: 100)
    response = find_items(
      operation: 'findCompletedItems',
      keyword: keyword,
      category_id: category_id,
      sold_items_only: true,
      entries_per_page: limit
    )

    items = extract_items(response)
    prices = items.map { |item| extract_price(item) }.compact

    return {} if prices.empty?

    {
      count: prices.length,
      average: (prices.sum / prices.length).round(2),
      min: prices.min,
      max: prices.max,
      median: calculate_median(prices)
    }
  rescue StandardError => e
    logger.error("Failed to get price stats: #{e.message}")
    {}
  end

  # URLパラメータから価格統計を取得
  #
  # @param url_params [Hash] EbayUrlParser.parse の結果
  # @param limit [Integer] 取得件数
  # @return [Hash] 価格統計情報
  def get_price_stats_from_params(url_params, limit: 100)
    get_sold_price_stats(
      keyword: url_params[:keyword],
      category_id: url_params[:category_id],
      limit: limit
    )
  end

  # 価格帯分布を取得
  #
  # @param keyword [String] 検索キーワード
  # @param category_id [String] カテゴリID
  # @param ranges [Array<Hash>] 価格帯定義（省略時は自動計算）
  # @param limit [Integer] 取得件数
  # @return [Hash] 価格帯分布情報
  def get_price_distribution(keyword:, category_id: nil, ranges: nil, limit: 100)
    response = find_items(
      operation: 'findCompletedItems',
      keyword: keyword,
      category_id: category_id,
      sold_items_only: true,
      entries_per_page: limit
    )

    items = extract_items(response)
    prices = items.map { |item| extract_price(item) }.compact

    return {} if prices.empty?

    # 価格帯が指定されていない場合は自動計算
    ranges ||= calculate_auto_ranges(prices)

    distribution = calculate_distribution(prices, ranges)
    volume_zone = find_volume_zone(distribution)
    sweet_spot = calculate_sweet_spot(prices)

    {
      total_count: prices.length,
      average: (prices.sum / prices.length).round(2),
      median: calculate_median(prices),
      min: prices.min,
      max: prices.max,
      ranges: distribution,
      volume_zone: volume_zone,
      sweet_spot: sweet_spot
    }
  rescue StandardError => e
    logger.error("Failed to get price distribution: #{e.message}")
    {}
  end

  # URLパラメータから価格帯分布を取得
  #
  # @param url_params [Hash] EbayUrlParser.parse の結果
  # @param limit [Integer] 取得件数
  # @return [Hash] 価格帯分布情報
  def get_price_distribution_from_params(url_params, limit: 100)
    get_price_distribution(
      keyword: url_params[:keyword],
      category_id: url_params[:category_id],
      limit: limit
    )
  end

  # 状態別の価格比較を取得
  #
  # @param keyword [String] 検索キーワード
  # @param category_id [String] カテゴリID
  # @param limit [Integer] 取得件数
  # @return [Hash] 状態別価格情報
  def get_price_by_condition(keyword:, category_id: nil, limit: 100)
    response = find_items(
      operation: 'findCompletedItems',
      keyword: keyword,
      category_id: category_id,
      sold_items_only: true,
      entries_per_page: limit
    )

    items = extract_items(response)
    
    # 状態別にグループ化
    grouped = items.group_by { |item| extract_condition(item) }

    result = {}
    grouped.each do |condition, condition_items|
      prices = condition_items.map { |item| extract_price(item) }.compact
      next if prices.empty?

      result[condition] = {
        count: prices.length,
        average: (prices.sum / prices.length).round(2),
        min: prices.min,
        max: prices.max,
        median: calculate_median(prices)
      }
    end

    result
  rescue StandardError => e
    logger.error("Failed to get price by condition: #{e.message}")
    {}
  end

  # 詳細な価格分析レポートを取得
  #
  # @param keyword [String] 検索キーワード
  # @param category_id [String] カテゴリID
  # @param limit [Integer] 取得件数
  # @return [Hash] 詳細価格分析
  def get_detailed_price_analysis(keyword:, category_id: nil, limit: 100)
    response = find_items(
      operation: 'findCompletedItems',
      keyword: keyword,
      category_id: category_id,
      sold_items_only: true,
      entries_per_page: limit
    )

    items = extract_items(response)
    prices = items.map { |item| extract_price(item) }.compact

    return {} if prices.empty?

    ranges = calculate_auto_ranges(prices)
    distribution = calculate_distribution(prices, ranges)

    {
      basic_stats: {
        count: prices.length,
        average: (prices.sum / prices.length).round(2),
        median: calculate_median(prices),
        min: prices.min,
        max: prices.max,
        std_dev: calculate_std_dev(prices)
      },
      distribution: distribution,
      volume_zone: find_volume_zone(distribution),
      sweet_spot: calculate_sweet_spot(prices),
      percentiles: {
        p10: calculate_percentile(prices, 10),
        p25: calculate_percentile(prices, 25),
        p50: calculate_percentile(prices, 50),
        p75: calculate_percentile(prices, 75),
        p90: calculate_percentile(prices, 90)
      },
      recommendation: generate_recommendation(prices, distribution)
    }
  rescue StandardError => e
    logger.error("Failed to get detailed price analysis: #{e.message}")
    {}
  end

  # URLパラメータから詳細価格分析を取得
  #
  # @param url_params [Hash] EbayUrlParser.parse の結果
  # @param limit [Integer] 取得件数
  # @return [Hash] 詳細価格分析
  def get_detailed_analysis_from_params(url_params, limit: 100)
    get_detailed_price_analysis(
      keyword: url_params[:keyword],
      category_id: url_params[:category_id],
      limit: limit
    )
  end

  # API 呼び出し間隔を設定
  #
  # @param seconds [Integer] 秒数
  def set_delay(seconds)
    @delay = seconds
  end

  private

  # Finding API を呼び出す
  def find_items(operation:, keyword:, category_id: nil, condition_id: nil,
                 listing_type: nil, sold_items_only: false, entries_per_page: 100)
    sleep(@delay) if @delay.positive?

    params = build_finding_api_params(
      operation: operation,
      keyword: keyword,
      category_id: category_id,
      condition_id: condition_id,
      listing_type: listing_type,
      sold_items_only: sold_items_only,
      entries_per_page: entries_per_page
    )

    connection = build_finding_connection
    response = connection.get('', params)

    logger.debug("Finding API response: #{response.status}")

    parse_finding_response(response.body, operation)
  end

  # Finding API のパラメータを構築
  def build_finding_api_params(operation:, keyword:, category_id:, condition_id:,
                                listing_type:, sold_items_only:, entries_per_page:)
    params = {
      'OPERATION-NAME' => operation,
      'SERVICE-VERSION' => '1.13.0',
      'SECURITY-APPNAME' => @app_id,
      'RESPONSE-DATA-FORMAT' => 'JSON',
      'REST-PAYLOAD' => 'true',
      'keywords' => keyword,
      'paginationInput.entriesPerPage' => entries_per_page
    }

    params['categoryId'] = category_id if category_id

    # アイテムフィルター
    filter_index = 0

    if condition_id
      params["itemFilter(#{filter_index}).name"] = 'Condition'
      params["itemFilter(#{filter_index}).value"] = condition_id
      filter_index += 1
    end

    if listing_type
      params["itemFilter(#{filter_index}).name"] = 'ListingType'
      params["itemFilter(#{filter_index}).value"] = listing_type
      filter_index += 1
    end

    if sold_items_only
      params["itemFilter(#{filter_index}).name"] = 'SoldItemsOnly'
      params["itemFilter(#{filter_index}).value"] = 'true'
      filter_index += 1
    end

    # 日本からの出品（LocatedIn=JP）
    params["itemFilter(#{filter_index}).name"] = 'LocatedIn'
    params["itemFilter(#{filter_index}).value"] = 'JP'

    params
  end

  # Finding API 用の接続を構築
  def build_finding_connection
    Faraday.new(url: FINDING_API_URL) do |f|
      f.request :retry, max: DEFAULT_RETRY_COUNT, interval: 1
      f.options.timeout = DEFAULT_TIMEOUT
      f.options.open_timeout = DEFAULT_TIMEOUT
      f.adapter Faraday.default_adapter
    end
  end

  # Finding API のレスポンスをパース
  def parse_finding_response(body, operation)
    data = Oj.load(body)
    
    response_key = "#{operation}Response"
    response_data = data[response_key]&.first

    unless response_data
      logger.warn("No response data for #{operation}")
      return nil
    end

    ack = response_data['ack']&.first
    unless ack == 'Success'
      error = response_data['errorMessage']&.first
      logger.warn("API returned #{ack}: #{error}")
    end

    response_data
  end

  # 総件数を抽出
  def extract_total_count(response)
    return 0 unless response

    response.dig('paginationOutput', 0, 'totalEntries', 0).to_i
  end

  # 商品リストを抽出
  def extract_items(response)
    return [] unless response

    response.dig('searchResult', 0, 'item') || []
  end

  # 価格を抽出
  def extract_price(item)
    price_data = item.dig('sellingStatus', 0, 'currentPrice', 0)
    return nil unless price_data

    price_data['__value__'].to_f
  end

  # 中央値を計算
  def calculate_median(prices)
    sorted = prices.sort
    mid = sorted.length / 2
    
    if sorted.length.odd?
      sorted[mid]
    else
      ((sorted[mid - 1] + sorted[mid]) / 2.0).round(2)
    end
  end

  # 標準偏差を計算
  def calculate_std_dev(prices)
    return 0 if prices.length < 2

    mean = prices.sum / prices.length.to_f
    variance = prices.map { |p| (p - mean)**2 }.sum / prices.length
    Math.sqrt(variance).round(2)
  end

  # パーセンタイルを計算
  def calculate_percentile(prices, percentile)
    sorted = prices.sort
    index = (percentile / 100.0 * (sorted.length - 1)).round
    sorted[index]
  end

  # 自動で価格帯を計算
  def calculate_auto_ranges(prices)
    min_price = prices.min
    max_price = prices.max
    range_span = max_price - min_price

    # 4〜6区間に分割
    if range_span <= 200
      step = 50
    elsif range_span <= 500
      step = 100
    elsif range_span <= 1000
      step = 200
    elsif range_span <= 2000
      step = 300
    else
      step = 500
    end

    ranges = []
    current = (min_price / step).floor * step

    while current < max_price
      range_end = current + step
      ranges << { min: current, max: range_end }
      current = range_end
    end

    # 最大6区間に制限
    if ranges.length > 6
      # 区間を再計算
      step = (range_span / 5.0).ceil
      step = ((step / 100.0).ceil * 100) # 100単位に丸める
      ranges = []
      current = (min_price / step).floor * step
      while current < max_price && ranges.length < 6
        range_end = current + step
        ranges << { min: current, max: range_end }
        current = range_end
      end
    end

    ranges
  end

  # 価格帯ごとの分布を計算
  def calculate_distribution(prices, ranges)
    total = prices.length.to_f

    ranges.map do |range|
      count = prices.count { |p| p >= range[:min] && p < range[:max] }
      # 最後の区間は上限を含む
      if range == ranges.last
        count = prices.count { |p| p >= range[:min] && p <= range[:max] }
      end

      percentage = ((count / total) * 100).round(1)

      {
        range: "$#{range[:min].to_i}-#{range[:max].to_i}",
        min: range[:min],
        max: range[:max],
        count: count,
        percentage: percentage,
        bar: generate_bar(percentage)
      }
    end
  end

  # プログレスバーを生成
  def generate_bar(percentage, width: 20)
    filled = (percentage / 100.0 * width).round
    '█' * filled + '░' * (width - filled)
  end

  # 最も売れている価格帯（ボリュームゾーン）を特定
  def find_volume_zone(distribution)
    max_range = distribution.max_by { |d| d[:count] }
    max_range ? max_range[:range] : nil
  end

  # 仕入れ推奨価格帯（スイートスポット）を計算
  # 下位25%〜中央値の範囲を推奨
  def calculate_sweet_spot(prices)
    sorted = prices.sort
    p25 = calculate_percentile(prices, 25)
    p50 = calculate_percentile(prices, 50)

    {
      min: p25.round(2),
      max: p50.round(2),
      range: "$#{p25.to_i}-#{p50.to_i}",
      description: '仕入れ推奨価格帯（下位25%〜中央値）'
    }
  end

  # 仕入れ推奨を生成
  def generate_recommendation(prices, distribution)
    avg = prices.sum / prices.length.to_f
    median = calculate_median(prices)
    p25 = calculate_percentile(prices, 25)
    volume_zone = find_volume_zone(distribution)

    {
      target_buy_price_usd: (p25 * 0.6).round(2),  # 25%タイルの60%
      target_sell_price_usd: median,
      expected_profit_margin: (((median - p25 * 0.6) / (p25 * 0.6)) * 100).round(1),
      volume_zone: volume_zone,
      advice: generate_advice(prices, distribution)
    }
  end

  # アドバイスを生成
  def generate_advice(prices, distribution)
    avg = prices.sum / prices.length.to_f
    median = calculate_median(prices)
    std_dev = calculate_std_dev(prices)
    cv = (std_dev / avg * 100).round(1)  # 変動係数

    advice = []

    if cv > 50
      advice << '価格のばらつきが大きい。状態による価格差が顕著'
    elsif cv < 20
      advice << '価格が安定している。相場が読みやすい'
    end

    if prices.length >= 50
      advice << '取引量が多く、需要は安定'
    elsif prices.length < 20
      advice << '取引量が少なめ。ニッチ市場の可能性'
    end

    advice.join('。')
  end

  # 商品状態を抽出
  def extract_condition(item)
    condition_id = item.dig('condition', 0, 'conditionId', 0)
    
    case condition_id
    when '1000' then 'new'
    when '1500' then 'open_box'
    when '2000', '2500' then 'refurbished'
    when '3000' then 'used'
    when '4000' then 'used_very_good'
    when '5000' then 'used_good'
    when '6000' then 'used_acceptable'
    when '7000' then 'for_parts'
    else 'unknown'
    end
  end
end
