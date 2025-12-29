# frozen_string_literal: true

require 'sequel'

# データベース接続とマイグレーション管理
module Database
  class << self
    # データベースファイルのパス
    def db_path
      File.expand_path('../ebay_research.db', __FILE__)
    end

    # データベース接続を取得
    # @return [Sequel::Database]
    def connection
      @connection ||= Sequel.sqlite(db_path)
    end

    # マイグレーションを実行
    def migrate!
      Sequel.extension :migration
      migrations_path = File.expand_path('migrations', __dir__)
      Sequel::Migrator.run(connection, migrations_path)
    end

    # マイグレーションのバージョンを取得
    # @return [Integer]
    def current_version
      Sequel.extension :migration
      Sequel::Migrator.get_current_migration_version(connection)
    rescue StandardError
      0
    end

    # 接続をリセット（テスト用）
    def reset!
      @connection = nil
    end
  end
end

# モデルのベースクラス設定
DB = Database.connection
