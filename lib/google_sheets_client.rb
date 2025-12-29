# frozen_string_literal: true

require 'google/apis/sheets_v4'
require 'googleauth'

# Google Sheets API を操作するクライアントクラス
class GoogleSheetsClient
  # スプレッドシートの列定義
  COLUMNS = {
    no: 'A',
    category: 'B',
    maker: 'C',
    product_name: 'D',
    ebay_active_url: 'E',
    ebay_sold_url: 'F',
    active_count: 'G',
    sold_count: 'H',
    balance: 'I',
    avg_price_usd: 'J',
    avg_price_jpy: 'K',
    min_price_usd: 'L',
    max_price_usd: 'M',
    price_updated_at: 'N'
  }.freeze

  # ヘッダー行
  HEADER_ROW = 1

  # データ開始行
  DATA_START_ROW = 2

  attr_reader :spreadsheet_id, :sheet_name

  # @param spreadsheet_id [String] スプレッドシートID
  # @param sheet_name [String] シート名
  # @param credentials_path [String] 認証ファイルのパス
  def initialize(spreadsheet_id:, sheet_name:, credentials_path:)
    @spreadsheet_id = spreadsheet_id
    @sheet_name = sheet_name
    @credentials_path = credentials_path
    @service = build_service
  end

  # 全データを読み込む
  #
  # @return [Array<Hash>] 商品データの配列
  def read_all_products
    range = "#{sheet_name}!A#{DATA_START_ROW}:F"
    response = @service.get_spreadsheet_values(spreadsheet_id, range)
    
    return [] unless response.values

    response.values.map.with_index(DATA_START_ROW) do |row, index|
      parse_row(row, index)
    end.compact
  end

  # 指定範囲のデータを読み込む
  #
  # @param start_row [Integer] 開始行
  # @param end_row [Integer] 終了行
  # @return [Array<Hash>] 商品データの配列
  def read_products(start_row:, end_row:)
    range = "#{sheet_name}!A#{start_row}:F#{end_row}"
    response = @service.get_spreadsheet_values(spreadsheet_id, range)
    
    return [] unless response.values

    response.values.map.with_index(start_row) do |row, index|
      parse_row(row, index)
    end.compact
  end

  # 出品数・落札数・バランスを更新
  #
  # @param row_number [Integer] 行番号
  # @param active_count [Integer] 出品数
  # @param sold_count [Integer] 落札数
  # @param balance [Float] バランス（売れ行き率）
  def update_counts(row_number:, active_count:, sold_count:, balance:)
    range = "#{sheet_name}!G#{row_number}:I#{row_number}"
    values = [[active_count, sold_count, balance&.round(2)]]
    
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    
    @service.update_spreadsheet_value(
      spreadsheet_id,
      range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
  end

  # 出品数・落札数・バランス・価格情報をまとめて更新
  #
  # @param row_number [Integer] 行番号
  # @param active_count [Integer] 出品数
  # @param sold_count [Integer] 落札数
  # @param balance [Float] バランス
  # @param avg_price_usd [Float] 平均価格（USD）
  # @param avg_price_jpy [Integer] 平均価格（JPY）
  # @param min_price_usd [Float] 最低価格（USD）
  # @param max_price_usd [Float] 最高価格（USD）
  def update_all_data(row_number:, active_count:, sold_count:, balance:,
                      avg_price_usd: nil, avg_price_jpy: nil, 
                      min_price_usd: nil, max_price_usd: nil)
    range = "#{sheet_name}!G#{row_number}:N#{row_number}"
    values = [[
      active_count,
      sold_count,
      balance&.round(2),
      avg_price_usd&.round(2),
      avg_price_jpy,
      min_price_usd&.round(2),
      max_price_usd&.round(2),
      Time.now.strftime('%Y-%m-%d %H:%M')
    ]]
    
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    
    @service.update_spreadsheet_value(
      spreadsheet_id,
      range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
  end

  # 複数行をまとめて更新（バッチ更新）
  #
  # @param updates [Array<Hash>] 更新データの配列
  #   - :row_number [Integer] 行番号
  #   - :active_count [Integer] 出品数
  #   - :sold_count [Integer] 落札数
  #   - :balance [Float] バランス
  def batch_update_counts(updates)
    data = updates.map do |update|
      Google::Apis::SheetsV4::ValueRange.new(
        range: "#{sheet_name}!G#{update[:row_number]}:I#{update[:row_number]}",
        values: [[
          update[:active_count],
          update[:sold_count],
          update[:balance]&.round(2)
        ]]
      )
    end

    batch_update = Google::Apis::SheetsV4::BatchUpdateValuesRequest.new(
      value_input_option: 'USER_ENTERED',
      data: data
    )

    @service.batch_update_values(spreadsheet_id, batch_update)
  end

  # 複数行の全データをまとめて更新（価格情報含む）
  #
  # @param updates [Array<Hash>] 更新データの配列
  def batch_update_all_data(updates)
    data = updates.map do |update|
      Google::Apis::SheetsV4::ValueRange.new(
        range: "#{sheet_name}!G#{update[:row_number]}:N#{update[:row_number]}",
        values: [[
          update[:active_count],
          update[:sold_count],
          update[:balance]&.round(2),
          update[:avg_price_usd]&.round(2),
          update[:avg_price_jpy],
          update[:min_price_usd]&.round(2),
          update[:max_price_usd]&.round(2),
          Time.now.strftime('%Y-%m-%d %H:%M')
        ]]
      )
    end

    batch_update = Google::Apis::SheetsV4::BatchUpdateValuesRequest.new(
      value_input_option: 'USER_ENTERED',
      data: data
    )

    @service.batch_update_values(spreadsheet_id, batch_update)
  end

  # ヘッダー行を設定（新規シート用）
  def setup_headers
    headers = [
      'No', 'カテゴリ', 'メーカー', '商品名', 
      'ebay出品URL', 'ebay落札URL',
      '出品数', '落札数', 'バランス',
      '平均価格(USD)', '平均価格(JPY)', '最低価格(USD)', '最高価格(USD)',
      '更新日時'
    ]

    range = "#{sheet_name}!A1:N1"
    values = [headers]
    
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: values)
    
    @service.update_spreadsheet_value(
      spreadsheet_id,
      range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )
  end

  # 総行数を取得
  #
  # @return [Integer] データ行数（ヘッダー除く）
  def total_rows
    range = "#{sheet_name}!A:A"
    response = @service.get_spreadsheet_values(spreadsheet_id, range)
    
    return 0 unless response.values

    response.values.length - HEADER_ROW
  end

  # 特定メーカーのデータを取得
  #
  # @param maker [String] メーカー名
  # @return [Array<Hash>] 商品データの配列
  def read_products_by_maker(maker)
    read_all_products.select { |p| p[:maker]&.upcase == maker.upcase }
  end

  # 特定カテゴリのデータを取得
  #
  # @param category [String] カテゴリ名
  # @return [Array<Hash>] 商品データの配列
  def read_products_by_category(category)
    read_all_products.select { |p| p[:category] == category }
  end

  private

  # Google Sheets API サービスを構築
  def build_service
    service = Google::Apis::SheetsV4::SheetsService.new
    service.authorization = authorize
    service
  end

  # 認証
  def authorize
    scope = Google::Apis::SheetsV4::AUTH_SPREADSHEETS

    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(@credentials_path),
      scope: scope
    )
    authorizer.fetch_access_token!
    authorizer
  end

  # 行データをハッシュにパース
  def parse_row(row, row_number)
    return nil if row.nil? || row.empty? || row[0].nil?

    {
      row_number: row_number,
      no: row[0],
      category: row[1],
      maker: row[2],
      product_name: row[3],
      ebay_active_url: row[4],
      ebay_sold_url: row[5]
    }
  end
end
