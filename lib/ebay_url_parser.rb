# frozen_string_literal: true

require 'uri'
require 'cgi'

# eBay検索URLからパラメータを抽出するクラス
class EbayUrlParser
  # URLパラメータと内部キーのマッピング
  PARAM_MAPPING = {
    '_nkw' => :keyword,
    '_sacat' => :category_id,
    'LH_BIN' => :buy_it_now,
    'LH_PrefLoc' => :location,
    'LH_ItemCondition' => :condition,
    'LH_Sold' => :sold_only,
    'LH_Complete' => :completed,
    'LH_TitleDesc' => :title_desc_search
  }.freeze

  # 発送元フィルタのマッピング
  LOCATION_MAP = {
    '1' => 'US',
    '2' => 'Worldwide',
    '3' => 'NorthAmerica',
    '98' => 'Asia'
  }.freeze

  # 商品状態のマッピング
  CONDITION_MAP = {
    '1000' => 'New',
    '1500' => 'OpenBox',
    '2000' => 'Refurbished',
    '2500' => 'SellerRefurbished',
    '3000' => 'Used',
    '7000' => 'ForParts'
  }.freeze

  class << self
    # URLからパラメータを抽出
    #
    # @param url [String] eBay検索URL
    # @return [Hash] 抽出されたパラメータ
    def parse(url)
      return {} if url.nil? || url.empty?

      uri = URI.parse(url)
      return {} unless uri.query

      params = CGI.parse(uri.query)

      {
        keyword: extract_keyword(params),
        category_id: params['_sacat']&.first,
        buy_it_now: params['LH_BIN']&.first == '1',
        location: LOCATION_MAP[params['LH_PrefLoc']&.first],
        condition: CONDITION_MAP[params['LH_ItemCondition']&.first],
        condition_id: params['LH_ItemCondition']&.first,
        sold_only: params['LH_Sold']&.first == '1',
        completed: params['LH_Complete']&.first == '1',
        title_only: params['LH_TitleDesc']&.first == '0'
      }
    rescue URI::InvalidURIError => e
      warn "Invalid URL: #{url} - #{e.message}"
      {}
    end

    # 出品中URLかどうかを判定
    #
    # @param url [String] eBay検索URL
    # @return [Boolean]
    def active_listing_url?(url)
      params = parse(url)
      !params[:sold_only] && !params[:completed]
    end

    # 販売済みURLかどうかを判定
    #
    # @param url [String] eBay検索URL
    # @return [Boolean]
    def sold_listing_url?(url)
      params = parse(url)
      params[:sold_only] && params[:completed]
    end

    # URLからキーワードのみを抽出
    #
    # @param url [String] eBay検索URL
    # @return [String, nil]
    def extract_keyword_from_url(url)
      params = parse(url)
      params[:keyword]
    end

    private

    # キーワードを抽出（URLデコード済み）
    def extract_keyword(params)
      keyword = params['_nkw']&.first
      return nil if keyword.nil? || keyword.empty?

      # URLエンコードされている場合はデコード
      CGI.unescape(keyword)
    rescue StandardError
      keyword
    end
  end
end
