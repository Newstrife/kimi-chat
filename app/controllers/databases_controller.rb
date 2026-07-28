# frozen_string_literal: true

# 企业数据库数据源只读管理页。
#
# 数据源列表：GET /databases
# 连接测试：  GET /databases/test?name=xxx -> {ok, tables} 或 {ok: false, error}
class DatabasesController < ApplicationController
  def index
    @sources = EnterpriseQueryService.config.map do |name, cfg|
      next unless cfg.is_a?(Hash)

      source = {
        name: name.to_s,
        adapter: cfg["adapter"].to_s,
        address: address_of(cfg),
        enabled: !!cfg["enabled"],
        max_rows: EnterpriseQueryService.max_rows(cfg)
      }
      if source[:enabled]
        result = test_connection(source[:name])
        source[:ok] = result[:ok]
        source[:error] = result[:error]
        source[:tables] = result[:tables]
      end
      source
    end.compact
  end

  def test
    name = params[:name].to_s
    return render json: { ok: false, error: "缺少 name 参数" }, status: :bad_request if name.empty?

    render json: test_connection(name)
  end

  private

  def address_of(cfg)
    if cfg["adapter"].to_s == "sqlite3"
      cfg["database"].to_s
    else
      "#{cfg['host']}:#{cfg['port']}/#{cfg['database']}"
    end
  end

  def test_connection(name)
    tables = EnterpriseQueryService.tables(source: name, ip: request.remote_ip)
    { ok: true, tables: tables }
  rescue StandardError => e
    { ok: false, error: e.message }
  end
end
