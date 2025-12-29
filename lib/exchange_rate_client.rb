# frozen_string_literal: true

require 'faraday'
require 'oj'
require 'logger'

# 為替レートを取得するクライアントクラス
class ExchangeRateClient
  # 無料の為替レートAPI
  # open.er-api.com は登録不要で使える
  DEFAULT_API_URL = 'https://open.er-api.com/v6/latest/USD'

  # キャッシュファイル
  CACHE_FILE = 'tmp/exchange_rate_cache.json'

  # キャッシュの有効期限（秒）
  CACHE_TTL = 24 * 60 * 60  # 24時間

  attr_reader :logger

  # @param api_key [String, nil] APIキー（有料プランの場合）
  # @param logger [Logger] ロガー
  def initialize(api_key: nil, logger: nil)
    @api_key = api_key
    @logger = logger || Logger.new($stdout)
  end

  # USD/JPY レートを取得
  #
  # @param use_cache [Boolean] キャッシュを使用するか
  # @return [Float] USD/JPY レート
  def usd_to_jpy(use_cache: true)
    if use_cache
      cached = load_cache
      return cached[:rate] if cached && cache_valid?(cached)
    end

    rate = fetch_rate('JPY')
    save_cache(rate) if rate

    rate
  end

  # USD金額をJPYに変換
  #
  # @param usd_amount [Float] USD金額
  # @return [Integer] JPY金額（切り捨て）
  def convert_usd_to_jpy(usd_amount)
    return nil if usd_amount.nil?

    rate = usd_to_jpy
    return nil unless rate

    (usd_amount * rate).floor
  end

  # 複数のUSD金額をJPYに変換
  #
  # @param usd_amounts [Array<Float>] USD金額の配列
  # @return [Array<Integer>] JPY金額の配列
  def convert_all_usd_to_jpy(usd_amounts)
    rate = usd_to_jpy
    return [] unless rate

    usd_amounts.map { |amount| amount ? (amount * rate).floor : nil }
  end

  # 現在のレートと取得日時を取得
  #
  # @return [Hash] レート情報
  def current_rate_info
    cached = load_cache
    
    if cached && cache_valid?(cached)
      {
        rate: cached[:rate],
        fetched_at: Time.at(cached[:fetched_at]),
        source: 'cache'
      }
    else
      rate = fetch_rate('JPY')
      {
        rate: rate,
        fetched_at: Time.now,
        source: 'api'
      }
    end
  end

  # キャッシュをクリア
  def clear_cache
    File.delete(CACHE_FILE) if File.exist?(CACHE_FILE)
    logger.info('Exchange rate cache cleared')
  end

  private

  # APIからレートを取得
  def fetch_rate(target_currency)
    logger.info("Fetching exchange rate for #{target_currency}...")

    response = connection.get('')
    
    unless response.success?
      logger.error("Failed to fetch exchange rate: #{response.status}")
      return nil
    end

    data = Oj.load(response.body)
    
    unless data['result'] == 'success'
      logger.error("API error: #{data['error-type']}")
      return nil
    end

    rate = data.dig('rates', target_currency)
    logger.info("Fetched USD/#{target_currency} rate: #{rate}")

    rate
  rescue StandardError => e
    logger.error("Exchange rate fetch error: #{e.message}")
    nil
  end

  # HTTP接続を構築
  def connection
    @connection ||= Faraday.new(url: api_url) do |f|
      f.options.timeout = 10
      f.options.open_timeout = 10
      f.adapter Faraday.default_adapter
    end
  end

  # APIのURLを取得
  def api_url
    if @api_key
      # 有料プラン用URL（例：exchangerate-api.com）
      "https://v6.exchangerate-api.com/v6/#{@api_key}/latest/USD"
    else
      DEFAULT_API_URL
    end
  end

  # キャッシュを読み込み
  def load_cache
    return nil unless File.exist?(CACHE_FILE)

    data = Oj.load(File.read(CACHE_FILE))
    {
      rate: data['rate'],
      fetched_at: data['fetched_at']
    }
  rescue StandardError => e
    logger.warn("Failed to load cache: #{e.message}")
    nil
  end

  # キャッシュを保存
  def save_cache(rate)
    data = {
      'rate' => rate,
      'fetched_at' => Time.now.to_i
    }

    File.write(CACHE_FILE, Oj.dump(data))
    logger.debug("Exchange rate cached: #{rate}")
  rescue StandardError => e
    logger.warn("Failed to save cache: #{e.message}")
  end

  # キャッシュが有効かどうか
  def cache_valid?(cached)
    return false unless cached && cached[:fetched_at]

    Time.now.to_i - cached[:fetched_at] < CACHE_TTL
  end
end
