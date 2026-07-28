# frozen_string_literal: true

require "sqlite3"
require "timeout"
require "erb"
require "yaml"

# 企业数据库服务：只读访问企业数据库，支持多数据源。
#
# 数据源在 config/enterprise_databases.yml 中配置（ERB 渲染），每个数据源有
# 独立的名字、adapter（sqlite3/postgresql/mysql2/sqlserver）、行数限制和超时。
#
# 安全约束（对所有 adapter 一致）：
# - 仅允许 SELECT 开头的查询
# - 行数限制（sqlite/pg/mysql 用 LIMIT 包装子查询，sqlserver 用 SELECT TOP n 包装）
# - 超时（连接参数 + Timeout.timeout 兜底）
# - 每次查询写 AuditLog（detail 里带数据源名）
#
# postgresql / mysql2 / sqlserver 对应的 gem（pg / mysql2 / tiny_tds）按需延迟
# 加载，未安装时抛出友好错误，不影响应用启动。
class EnterpriseQueryService
  DEFAULT_MAX_ROWS = 100
  DEFAULT_TIMEOUT_SECONDS = 5
  DEFAULT_SAMPLE_ROWS = 10

  SUPPORTED_ADAPTERS = %w[sqlite3 postgresql mysql2 sqlserver].freeze

  # adapter 对应的 gem 名及 Gemfile 提示
  ADAPTER_GEMS = {
    "postgresql" => "pg",
    "mysql2" => "mysql2",
    "sqlserver" => "tiny_tds"
  }.freeze

  class Error < StandardError; end

  # ---------------- 配置 ----------------

  def self.config
    @config ||= begin
      path = Rails.root.join("config/enterprise_databases.yml")
      raw = ERB.new(File.read(path)).result
      yaml = YAML.safe_load(raw, aliases: true) || {}
      yaml.fetch(Rails.env, {}) || {}
    end
  end

  # 测试或修改配置后调用，清除缓存
  def self.reset_config!
    @config = nil
  end

  # 返回 enabled 数据源列表：[{ name:, adapter: }]
  def self.sources
    config.filter_map do |name, cfg|
      next unless cfg.is_a?(Hash) && cfg["enabled"]

      { name: name.to_s, adapter: cfg["adapter"].to_s }
    end
  end

  # 返回数据源完整配置（含名称），未配置或未启用时抛错
  def self.source_config(source)
    cfg = config[source.to_s]
    raise Error, "未知数据源: #{source}（请检查 config/enterprise_databases.yml）" unless cfg.is_a?(Hash)
    raise Error, "数据源 #{source} 未启用" unless cfg["enabled"]

    cfg
  end

  def self.max_rows(cfg)
    (cfg["max_rows"] || DEFAULT_MAX_ROWS).to_i
  end

  def self.timeout_seconds(cfg)
    (cfg["timeout_seconds"] || DEFAULT_TIMEOUT_SECONDS).to_i
  end

  def self.sample_rows(cfg)
    (cfg["sample_rows"] || DEFAULT_SAMPLE_ROWS).to_i
  end

  # 兼容旧接口：company SQLite 数据源的默认路径
  def self.db_path
    ENV["ENTERPRISE_DB_PATH"] || EnterpriseFileService.root.join("company.db").to_s
  end

  # ---------------- 查询 ----------------

  # 执行只读 SELECT 查询，返回 { columns:, rows: }
  def self.query(sql, source: :company, ip: nil)
    cfg = source_config(source)
    result = execute(sql, cfg, check_select: true)
    audit(source, sql, ip)
    result
  end

  # 表名列表
  def self.tables(source: :company, ip: nil)
    cfg = source_config(source)
    sql = case adapter(cfg)
          when "sqlite3"
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
          when "postgresql"
            "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name"
          when "mysql2"
            "SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE() ORDER BY table_name"
          when "sqlserver"
            "SELECT TABLE_NAME FROM information_schema.tables WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME"
          end
    result = execute(sql, cfg, check_select: true)
    audit(source, sql, ip)
    result[:rows].flatten
  end

  # 表结构摘要（供检索注入使用）
  def self.schema_summary(source: :company, ip: nil)
    cfg = source_config(source)
    tables(source: source, ip: ip).map do |table|
      cols = columns_for(table, cfg, source, ip)
      "#{table}(#{cols.join(', ')})"
    end.join("\n")
  end

  # ---------------- 内部实现 ----------------

  def self.adapter(cfg)
    ad = cfg["adapter"].to_s
    raise Error, "不支持的 adapter: #{ad}（支持：#{SUPPORTED_ADAPTERS.join(', ')}）" unless SUPPORTED_ADAPTERS.include?(ad)

    ad
  end

  # 统一执行入口：SELECT 校验（可关）+ 行数限制 + 超时 + adapter 分发
  def self.execute(sql, cfg, check_select:, limit: true)
    sql = sql.to_s.strip
    raise Error, "仅允许 SELECT 查询" if check_select && !sql.match?(/\ASELECT\b/i)

    final_sql = limit ? wrap_limit(sql, cfg) : sql
    Timeout.timeout(timeout_seconds(cfg)) { dispatch(adapter(cfg), final_sql, cfg) }
  rescue Timeout::Error
    raise Error, "查询超时（#{timeout_seconds(cfg)} 秒）"
  end

  # 行数限制包装：sqlserver 用 SELECT TOP n，其余用 LIMIT 子查询
  def self.wrap_limit(sql, cfg)
    inner = sql.sub(/;+\s*\z/, "")
    if adapter(cfg) == "sqlserver"
      "SELECT TOP #{max_rows(cfg)} * FROM (#{inner}) AS q"
    else
      "SELECT * FROM (#{inner}) AS q LIMIT #{max_rows(cfg)}"
    end
  end

  def self.dispatch(adapter, sql, cfg)
    case adapter
    when "sqlite3" then exec_sqlite3(sql, cfg)
    when "postgresql" then exec_postgresql(sql, cfg)
    when "mysql2" then exec_mysql2(sql, cfg)
    when "sqlserver" then exec_sqlserver(sql, cfg)
    end
  end

  # 延迟加载 adapter gem，未安装时给出友好提示（绝不让应用启动崩溃）
  def self.require_adapter_gem!(adapter)
    gem_name = ADAPTER_GEMS.fetch(adapter)
    require gem_name
  rescue LoadError
    raise Error, "#{adapter} 数据源需要 gem \"#{gem_name}\"：请在 Gemfile 中取消对应注释并运行 bundle install"
  end

  def self.exec_sqlite3(sql, cfg)
    db = SQLite3::Database.new(cfg["database"].to_s, readonly: true)
    db.busy_timeout = timeout_seconds(cfg) * 1000
    result = db.execute2(sql)
    { columns: result.first || [], rows: result[1..] || [] }
  ensure
    db&.close
  end

  def self.exec_postgresql(sql, cfg)
    require_adapter_gem!("postgresql")
    conn = PG.connect(
      host: cfg["host"], port: (cfg["port"] || 5432).to_i, dbname: cfg["database"],
      user: cfg["username"], password: cfg["password"],
      connect_timeout: timeout_seconds(cfg)
    )
    result = conn.exec(sql)
    { columns: result.fields, rows: result.values }
  ensure
    conn&.close
  end

  def self.exec_mysql2(sql, cfg)
    require_adapter_gem!("mysql2")
    client = Mysql2::Client.new(
      host: cfg["host"], port: (cfg["port"] || 3306).to_i, database: cfg["database"],
      username: cfg["username"], password: cfg["password"],
      connect_timeout: timeout_seconds(cfg), read_timeout: timeout_seconds(cfg)
    )
    result = client.query(sql)
    { columns: result.fields, rows: result.map(&:values) }
  ensure
    client&.close
  end

  def self.exec_sqlserver(sql, cfg)
    require_adapter_gem!("sqlserver")
    client = TinyTds::Client.new(
      host: cfg["host"], port: (cfg["port"] || 1433).to_i, database: cfg["database"],
      username: cfg["username"], password: cfg["password"],
      timeout: timeout_seconds(cfg), login_timeout: timeout_seconds(cfg)
    )
    result = client.execute(sql)
    { columns: result.fields, rows: result.each(as: :array) }
  ensure
    result&.cancel
    client&.close
  end

  # 单表字段清单（"name TYPE" 格式），供 schema_summary 使用
  def self.columns_for(table, cfg, source, ip)
    case adapter(cfg)
    when "sqlite3"
      sql = "PRAGMA table_info(#{table})"
      result = execute(sql, cfg, check_select: false, limit: false)
      audit(source, sql, ip)
      result[:rows].map { |row| "#{row[1]} #{row[2]}" }
    else
      schema_cond = case adapter(cfg)
                    when "postgresql" then "table_schema='public'"
                    when "mysql2" then "table_schema=DATABASE()"
                    when "sqlserver" then "1=1"
                    end
      sql = "SELECT column_name, data_type FROM information_schema.columns " \
            "WHERE #{schema_cond} AND table_name=#{quote_string(table)} ORDER BY ordinal_position"
      result = execute(sql, cfg, check_select: true)
      audit(source, sql, ip)
      result[:rows].map { |name, type| "#{name} #{type}" }
    end
  end

  def self.quote_string(value)
    "'#{value.to_s.gsub("'", "''")}'"
  end

  def self.audit(source, sql, ip)
    AuditLog.create!(action: "sql_query", detail: "[#{source}] #{sql.to_s.truncate(490)}", ip: ip)
  end
end
