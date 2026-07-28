# 多数据源体系自检脚本：bin/rails runner check_datasources.rb

failures = []
check = lambda do |name, ok, extra = ""|
  puts format("%-40s %s %s", name, ok ? "PASS" : "FAIL", extra)
  failures << name unless ok
end

# 1. sources 列表
sources = EnterpriseQueryService.sources
puts "sources = #{sources.inspect}"
check.call("sources 包含 company/sqlite3",
           sources.any? { |s| s[:name] == "company" && s[:adapter] == "sqlite3" })

# 2. company 源查询 departments
result = EnterpriseQueryService.query("SELECT * FROM departments", source: :company)
check.call("SELECT * FROM departments 返回 4 行", result[:rows].size == 4,
           "实际 #{result[:rows].size} 行, columns=#{result[:columns].inspect}")

# 3. schema_summary
summary = EnterpriseQueryService.schema_summary(source: :company)
puts "---- schema_summary(company) ----"
puts summary
puts "---------------------------------"
check.call("schema_summary 非空且包含 departments", summary.present? && summary.include?("departments"))

# 4. 非 SELECT 被拦截
begin
  EnterpriseQueryService.query("DELETE FROM departments", source: :company)
  check.call("非 SELECT 查询被拦截", false, "DELETE 竟然执行了")
rescue EnterpriseQueryService::Error => e
  check.call("非 SELECT 查询被拦截", e.message.include?("SELECT"), e.message)
end

# 5. 缺 gem 的数据源抛出友好错误（不崩溃）
begin
  EnterpriseQueryService.query("SELECT 1", source: :nonexistent)
  check.call("未知数据源报错", false)
rescue EnterpriseQueryService::Error => e
  check.call("未知数据源报错", e.message.include?("未知数据源"), e.message)
end

# 6. /databases 页面 HTTP 200（用 Rack::Test 直接打应用，无需起服务器）
require "rack/test"
app = Rails.application
session = Rack::Test::Session.new(Rack::MockSession.new(app))
session.basic_authorize(ENV.fetch("KIMI_CHAT_USER", "admin"), ENV.fetch("KIMI_CHAT_PASSWORD", "admin123"))
session.get "/databases"
check.call("GET /databases 返回 200", session.last_response.status == 200,
           "实际 #{session.last_response.status}")
check.call("/databases 页面包含 company", session.last_response.body.include?("company"))

session.get "/databases/test", { name: "company" }
check.call("GET /databases/test?name=company 成功",
           session.last_response.status == 200 && JSON.parse(session.last_response.body)["ok"] == true,
           session.last_response.body[0, 120])

# 7. 检索注入包含数据库来源
built = EnterpriseRetriever.build_context("部门有哪些")
db_sources = built[:sources].select { |s| s[:type] == "database" }
check.call("检索注入含 database 来源", db_sources.any? { |s| s[:name] == "company (sqlite3)" },
           db_sources.inspect)

puts
if failures.empty?
  puts "全部自检通过 ✅"
else
  puts "失败项: #{failures.join(', ')}"
  exit 1
end
