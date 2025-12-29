#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load'
require 'thor'
require 'logger'
require 'ruby-progressbar'

# lib ディレクトリを読み込みパスに追加
$LOAD_PATH.unshift(File.join(__dir__, '..', 'lib'))

require 'google_sheets_client'
require 'ebay_url_parser'
require 'ebay_api_client'
require 'balance_calculator'
require 'exchange_rate_client'

# db ディレクトリを読み込みパスに追加
$LOAD_PATH.unshift(File.join(__dir__, '..', 'db'))

# Note: history_analyzer は DB依存のため、必要時に遅延ロードする

# eBay カメラリサーチツール CLI
class EbayCameraResearchCLI < Thor
  class_option :verbose, type: :boolean, default: false, desc: '詳細ログを出力'

  desc 'fetch_all', '全商品のデータを取得（API制限により複数日かかる場合あり）'
  option :dry_run, type: :boolean, default: false, desc: '実際にはAPIを呼ばない'
  option :delay, type: :numeric, default: 1, desc: 'API呼び出し間隔（秒）'
  option :with_price, type: :boolean, default: false, desc: '価格情報も取得'
  option :save_history, type: :boolean, default: true, desc: '履歴をDBに保存'
  def fetch_all
    setup_logger
    logger.info('Starting fetch_all...')

    products = sheets_client.read_all_products
    logger.info("Total products: #{products.length}")

    process_products(products, dry_run: options[:dry_run], delay: options[:delay], with_price: options[:with_price], save_history: options[:save_history])
  end

  desc 'fetch_batch BATCH_NUMBER', '指定バッチのデータを取得（1バッチ=500件）'
  option :batch_size, type: :numeric, default: 500, desc: 'バッチサイズ'
  option :dry_run, type: :boolean, default: false, desc: '実際にはAPIを呼ばない'
  option :delay, type: :numeric, default: 1, desc: 'API呼び出し間隔（秒）'
  option :with_price, type: :boolean, default: false, desc: '価格情報も取得'
  option :save_history, type: :boolean, default: true, desc: '履歴をDBに保存'
  def fetch_batch(batch_number)
    setup_logger
    batch_num = batch_number.to_i
    batch_size = options[:batch_size]

    start_row = (batch_num - 1) * batch_size + 2  # +2 はヘッダー行分
    end_row = start_row + batch_size - 1

    logger.info("Fetching batch #{batch_num}: rows #{start_row} to #{end_row}")

    products = sheets_client.read_products(start_row: start_row, end_row: end_row)
    logger.info("Products in batch: #{products.length}")

    process_products(products, dry_run: options[:dry_run], delay: options[:delay], with_price: options[:with_price], save_history: options[:save_history])
  end

  desc 'fetch_maker MAKER', '指定メーカーのデータを取得'
  option :dry_run, type: :boolean, default: false, desc: '実際にはAPIを呼ばない'
  option :delay, type: :numeric, default: 1, desc: 'API呼び出し間隔（秒）'
  option :with_price, type: :boolean, default: false, desc: '価格情報も取得'
  option :save_history, type: :boolean, default: true, desc: '履歴をDBに保存'
  def fetch_maker(maker)
    setup_logger
    logger.info("Fetching maker: #{maker}")

    products = sheets_client.read_products_by_maker(maker)
    logger.info("Products for #{maker}: #{products.length}")

    process_products(products, dry_run: options[:dry_run], delay: options[:delay], with_price: options[:with_price], save_history: options[:save_history])
  end

  desc 'analyze_price KEYWORD', '指定キーワードの価格帯分析'
  option :category, type: :string, desc: 'eBayカテゴリID'
  option :limit, type: :numeric, default: 100, desc: '取得件数'
  def analyze_price(keyword)
    setup_logger

    puts '=' * 70
    puts "📊 価格帯分析: #{keyword}"
    puts '=' * 70

    analysis = ebay_client.get_detailed_price_analysis(
      keyword: keyword,
      category_id: options[:category],
      limit: options[:limit]
    )

    if analysis.empty?
      puts "\n❌ データが見つかりませんでした"
      return
    end

    # 基本統計
    stats = analysis[:basic_stats]
    puts "\n📈 基本統計"
    puts "   販売件数: #{stats[:count]}件（過去90日）"
    puts "   平均価格: $#{stats[:average]} (¥#{convert_to_jpy(stats[:average])})"
    puts "   中央値:   $#{stats[:median]} (¥#{convert_to_jpy(stats[:median])})"
    puts "   最低価格: $#{stats[:min]}"
    puts "   最高価格: $#{stats[:max]}"
    puts "   標準偏差: $#{stats[:std_dev]}"

    # パーセンタイル
    pct = analysis[:percentiles]
    puts "\n📊 パーセンタイル"
    puts "   10%: $#{pct[:p10]}  25%: $#{pct[:p25]}  50%: $#{pct[:p50]}  75%: $#{pct[:p75]}  90%: $#{pct[:p90]}"

    # 価格帯分布
    puts "\n📦 価格帯分布"
    analysis[:distribution].each do |d|
      puts "   #{d[:range].ljust(12)} #{d[:bar]} #{d[:count]}件 (#{d[:percentage]}%)"
    end

    # ボリュームゾーン・スイートスポット
    puts "\n🎯 分析結果"
    puts "   ボリュームゾーン: #{analysis[:volume_zone]}（最も取引が多い価格帯）"
    
    sweet = analysis[:sweet_spot]
    puts "   仕入れ推奨価格帯: #{sweet[:range]} (#{sweet[:description]})"

    # 推奨
    rec = analysis[:recommendation]
    puts "\n💡 仕入れ推奨"
    puts "   目標仕入れ価格: $#{rec[:target_buy_price_usd]} (¥#{convert_to_jpy(rec[:target_buy_price_usd])})"
    puts "   想定販売価格:   $#{rec[:target_sell_price_usd]} (¥#{convert_to_jpy(rec[:target_sell_price_usd])})"
    puts "   想定利益率:     #{rec[:expected_profit_margin]}%"
    puts "   アドバイス:     #{rec[:advice]}" if rec[:advice] && !rec[:advice].empty?

    puts "\n" + '=' * 70
  end

  desc 'analyze_row ROW_NUMBER', '指定行の商品の価格帯分析'
  option :limit, type: :numeric, default: 100, desc: '取得件数'
  def analyze_row(row_number)
    setup_logger

    products = sheets_client.read_products(start_row: row_number.to_i, end_row: row_number.to_i)
    product = products.first

    unless product
      puts "❌ 行 #{row_number} が見つかりませんでした"
      return
    end

    puts "商品: #{product[:product_name]}"
    puts "メーカー: #{product[:maker]}"
    puts "カテゴリ: #{product[:category]}"
    puts ""

    # URLからパラメータを抽出して分析
    sold_params = EbayUrlParser.parse(product[:ebay_sold_url])
    
    if sold_params[:keyword]
      analyze_price(sold_params[:keyword])
    else
      puts "❌ 検索キーワードを抽出できませんでした"
    end
  end

  desc 'price_comparison KEYWORD', '状態別の価格比較'
  option :category, type: :string, desc: 'eBayカテゴリID'
  option :limit, type: :numeric, default: 100, desc: '取得件数'
  def price_comparison(keyword)
    setup_logger

    puts '=' * 60
    puts "📊 状態別価格比較: #{keyword}"
    puts '=' * 60

    prices = ebay_client.get_price_by_condition(
      keyword: keyword,
      category_id: options[:category],
      limit: options[:limit]
    )

    if prices.empty?
      puts "\n❌ データが見つかりませんでした"
      return
    end

    condition_labels = {
      'new' => '新品',
      'open_box' => '開封済み',
      'refurbished' => 'リファービッシュ',
      'used' => '中古',
      'used_very_good' => '中古（非常に良い）',
      'used_good' => '中古（良い）',
      'used_acceptable' => '中古（可）',
      'for_parts' => 'ジャンク',
      'unknown' => '不明'
    }

    puts "\n状態           | 件数 | 平均価格    | 最低    | 最高    | 中央値"
    puts "-" * 70

    prices.sort_by { |_, v| -v[:average] }.each do |condition, data|
      label = condition_labels[condition] || condition
      puts "#{label.ljust(14)} | #{data[:count].to_s.rjust(4)} | $#{data[:average].to_s.rjust(8)} | $#{data[:min].to_s.rjust(6)} | $#{data[:max].to_s.rjust(6)} | $#{data[:median].to_s.rjust(6)}"
    end

    puts "\n" + '=' * 60
  end

  desc 'test_connection', 'API接続テスト'
  def test_connection
    setup_logger
    
    puts '=' * 50
    puts 'API Connection Test'
    puts '=' * 50

    # Google Sheets テスト
    puts "\n[Google Sheets API]"
    begin
      total = sheets_client.total_rows
      puts "✅ Connected. Total rows: #{total}"
    rescue StandardError => e
      puts "❌ Failed: #{e.message}"
    end

    # eBay API テスト
    puts "\n[eBay API]"
    begin
      count = ebay_client.get_active_listing_count(keyword: 'canon camera')
      puts "✅ Connected. Test search result: #{count} items"
    rescue StandardError => e
      puts "❌ Failed: #{e.message}"
    end

    # 為替レート テスト
    puts "\n[Exchange Rate API]"
    begin
      rate_info = exchange_client.current_rate_info
      puts "✅ USD/JPY: #{rate_info[:rate]} (source: #{rate_info[:source]})"
    rescue StandardError => e
      puts "❌ Failed: #{e.message}"
    end

    puts "\n" + '=' * 50
  end

  desc 'show_stats', '現在の統計情報を表示'
  def show_stats
    setup_logger

    products = sheets_client.read_all_products
    
    puts '=' * 60
    puts 'eBay Camera Research - Statistics'
    puts '=' * 60

    puts "\n📊 総商品数: #{products.length}"

    # カテゴリ別
    puts "\n📂 カテゴリ別:"
    products.group_by { |p| p[:category] }.each do |category, items|
      puts "   #{category}: #{items.length} 件"
    end

    # メーカー別（上位10）
    puts "\n�icing  メーカー別（上位10）:"
    products.group_by { |p| p[:maker] }
            .sort_by { |_, items| -items.length }
            .first(10)
            .each do |maker, items|
      puts "   #{maker}: #{items.length} 件"
    end
  end

  desc 'sample_parse', 'URL解析のサンプルを表示'
  option :row, type: :numeric, default: 2, desc: '解析する行番号'
  def sample_parse
    setup_logger

    products = sheets_client.read_products(start_row: options[:row], end_row: options[:row])
    product = products.first

    unless product
      puts "Row #{options[:row]} not found"
      return
    end

    puts '=' * 60
    puts 'URL Parse Sample'
    puts '=' * 60

    puts "\n📦 商品情報:"
    puts "   No: #{product[:no]}"
    puts "   カテゴリ: #{product[:category]}"
    puts "   メーカー: #{product[:maker]}"
    puts "   商品名: #{product[:product_name]}"

    puts "\n🔗 出品中URL:"
    puts "   #{product[:ebay_active_url]}"
    active_params = EbayUrlParser.parse(product[:ebay_active_url])
    puts "   → パラメータ: #{active_params}"

    puts "\n🔗 落札URL:"
    puts "   #{product[:ebay_sold_url]}"
    sold_params = EbayUrlParser.parse(product[:ebay_sold_url])
    puts "   → パラメータ: #{sold_params}"
  end

  # ========================================
  # データベース関連コマンド
  # ========================================

  desc 'db_migrate', 'データベースのマイグレーションを実行'
  def db_migrate
    require 'database'

    puts 'Running database migrations...'
    Database.migrate!
    puts "✅ Migration completed. Current version: #{Database.current_version}"
  end

  desc 'sync_to_db', 'スプレッドシートの商品データをDBに同期'
  def sync_to_db
    setup_logger
    require 'database'
    require 'models/product'

    puts 'Syncing products from spreadsheet to database...'

    products = sheets_client.read_all_products
    progressbar = ProgressBar.create(
      total: products.length,
      format: '%a %b▓%i %p%% %t',
      progress_mark: '█',
      remainder_mark: '░'
    )

    products.each do |sheet_product|
      Product.sync_from_sheet(sheet_product)
      progressbar.increment
    end

    puts "\n✅ Synced #{products.length} products to database"
  end

  desc 'trend PRODUCT_NAME', '商品のトレンド分析を表示'
  option :days, type: :numeric, default: 30, desc: '分析期間（日数）'
  def trend(product_name)
    require 'database'
    require 'models/product'
    require 'history_analyzer'

    products = Product.search_by_name(product_name)

    if products.empty?
      puts "❌ 商品「#{product_name}」が見つかりませんでした"
      puts '   ヒント: 先に sync_to_db コマンドでデータを同期してください'
      return
    end

    products.each do |product|
      puts HistoryAnalyzer.visualize_trend(product, days: options[:days])
      puts '' if products.length > 1
    end
  end

  desc 'price_changes', '価格変動レポートを表示'
  option :days, type: :numeric, default: 7, desc: '分析期間（日数）'
  option :threshold, type: :numeric, default: 10, desc: '変動率の閾値（%）'
  def price_changes
    require 'database'
    require 'models/product'
    require 'history_analyzer'

    threshold = options[:threshold] / 100.0
    puts HistoryAnalyzer.visualize_price_changes(days: options[:days], threshold: threshold)
  end

  desc 'rising_products', '上昇トレンドの商品一覧を表示'
  option :days, type: :numeric, default: 30, desc: '分析期間（日数）'
  option :limit, type: :numeric, default: 20, desc: '表示件数'
  def rising_products
    require 'database'
    require 'models/product'
    require 'history_analyzer'

    products = HistoryAnalyzer.rising_products(days: options[:days], limit: options[:limit])

    puts '=' * 70
    puts "📈 上昇トレンド商品（過去#{options[:days]}日）"
    puts '=' * 70

    if products.empty?
      puts "\n   該当する商品がありません"
      puts '   ヒント: データを蓄積するため、定期的に fetch_all を実行してください'
    else
      puts "\n   商品名                           | 現在バランス | 変動率"
      puts '   ' + '-' * 60

      products.each do |item|
        puts format('   %-35s | %11.2f | %+.1f%%',
                    truncate_name(item[:product].product_name, 35),
                    item[:current_balance] || 0,
                    item[:balance_change] || 0)
      end
    end

    puts "\n" + '=' * 70
  end

  private

  def truncate_name(str, length)
    return str if str.nil? || str.length <= length

    str[0, length - 3] + '...'
  end

  def setup_logger
    level = options[:verbose] ? Logger::DEBUG : Logger::INFO
    @logger = Logger.new($stdout)
    @logger.level = level
    @logger.formatter = proc do |severity, datetime, _, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
  end

  def logger
    @logger ||= Logger.new($stdout)
  end

  def sheets_client
    @sheets_client ||= GoogleSheetsClient.new(
      spreadsheet_id: ENV.fetch('GOOGLE_SPREADSHEET_ID'),
      sheet_name: ENV.fetch('GOOGLE_SHEET_NAME', 'all_sheets_combined'),
      credentials_path: ENV.fetch('GOOGLE_CREDENTIALS_PATH', './config/google_credentials.json')
    )
  end

  def ebay_client
    @ebay_client ||= EbayApiClient.new(
      app_id: ENV.fetch('EBAY_APP_ID'),
      oauth_token: ENV['EBAY_OAUTH_TOKEN'],
      environment: ENV.fetch('EBAY_ENVIRONMENT', 'production'),
      logger: logger
    )
  end

  def exchange_client
    @exchange_client ||= ExchangeRateClient.new(
      api_key: ENV['EXCHANGE_RATE_API_KEY'],
      logger: logger
    )
  end

  def process_products(products, dry_run:, delay:, with_price: false, save_history: true)
    return if products.empty?

    # 履歴保存が有効な場合はDBを初期化
    if save_history
      require 'database'
      require 'models/product'
      require 'models/snapshot'
      Database.migrate! # マイグレーションが未実行なら実行
    end

    ebay_client.set_delay(delay)

    updates = []
    progressbar = ProgressBar.create(
      total: products.length,
      format: '%a %b▓%i %p%% %t',
      progress_mark: '█',
      remainder_mark: '░'
    )

    products.each do |product|
      progressbar.increment

      if dry_run
        logger.debug("DRY RUN: Would process #{product[:product_name]}")
        next
      end

      begin
        result = fetch_product_data(product, with_price: with_price)

        if result
          updates << result

          # 履歴をDBに保存
          if save_history
            save_snapshot(product, result)
          end
        end
      rescue StandardError => e
        logger.error("Failed to process #{product[:product_name]}: #{e.message}")
      end

      # 50件ごとにスプレッドシート更新
      if updates.length >= 50
        update_spreadsheet(updates, with_price: with_price)
        updates = []
      end
    end

    # 残りを更新
    update_spreadsheet(updates, with_price: with_price) unless updates.empty?

    logger.info('Processing completed!')
    logger.info('Snapshots saved to database') if save_history
  end

  def save_snapshot(sheet_product, result)
    # 商品をDBに同期
    db_product = Product.sync_from_sheet(sheet_product)

    # スナップショットを保存
    Snapshot.record(db_product, result)
  rescue StandardError => e
    logger.warn("Failed to save snapshot for #{sheet_product[:product_name]}: #{e.message}")
  end

  def fetch_product_data(product, with_price: false)
    logger.debug("Processing: #{product[:product_name]}")

    # URL からパラメータを抽出
    active_params = EbayUrlParser.parse(product[:ebay_active_url])
    sold_params = EbayUrlParser.parse(product[:ebay_sold_url])

    # 出品数を取得
    active_count = ebay_client.get_active_count_from_params(active_params)
    
    # 落札数を取得
    sold_count = ebay_client.get_sold_count_from_params(sold_params)

    # バランスを計算
    balance = BalanceCalculator.calculate(
      sold_count: sold_count,
      active_count: active_count
    )

    result = {
      row_number: product[:row_number],
      active_count: active_count,
      sold_count: sold_count,
      balance: balance
    }

    # 価格情報を取得（オプション）
    if with_price
      price_stats = ebay_client.get_price_stats_from_params(sold_params)
      
      if price_stats && !price_stats.empty?
        result[:avg_price_usd] = price_stats[:average]
        result[:avg_price_jpy] = convert_to_jpy(price_stats[:average])
        result[:min_price_usd] = price_stats[:min]
        result[:max_price_usd] = price_stats[:max]
      end

      logger.info("#{product[:product_name]}: 出品#{active_count} / 落札#{sold_count} / バランス#{balance} / 平均$#{price_stats[:average]}")
    else
      logger.info("#{product[:product_name]}: 出品#{active_count} / 落札#{sold_count} / バランス#{balance}")
    end

    result
  end

  def update_spreadsheet(updates, with_price: false)
    return if updates.empty?

    logger.info("Updating spreadsheet: #{updates.length} rows")
    
    if with_price
      sheets_client.batch_update_all_data(updates)
    else
      sheets_client.batch_update_counts(updates)
    end
  end

  def convert_to_jpy(usd_amount)
    return nil if usd_amount.nil?
    exchange_client.convert_usd_to_jpy(usd_amount)
  end
end

# 実行
EbayCameraResearchCLI.start(ARGV)
