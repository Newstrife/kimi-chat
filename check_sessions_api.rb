# frozen_string_literal: true

# 自检脚本：bin/rails runner check_sessions_api.rb
# 用 Rack::Test（Basic 认证 admin/admin123）验证会话列表/删除接口
require "rack/test"
require "json"

include Rack::Test::Methods

def app
  Rails.application
end

basic_authorize "admin", "admin123"

# 1) GET /chat/sessions 返回 200 且是数组
get "/chat/sessions"
raise "FAIL: GET /chat/sessions status=#{last_response.status}" unless last_response.status == 200
list = JSON.parse(last_response.body)
raise "FAIL: GET /chat/sessions 返回不是数组" unless list.is_a?(Array)
puts "PASS: GET /chat/sessions -> 200, 数组（#{list.size} 条）"
if (s = list.first)
  %w[id title updated_at message_count preview].each do |k|
    raise "FAIL: 会话条目缺少字段 #{k}" unless s.key?(k)
  end
  puts "PASS: 条目字段完整（id/title/updated_at/message_count/preview）"
end

# 2) POST 一条消息后出现新会话条目
post "/chat/ask", { prompt: "自检测试：接口验证" }.to_json, { "CONTENT_TYPE" => "application/json" }
raise "FAIL: POST /chat/ask status=#{last_response.status}" unless last_response.status == 200
new_id = JSON.parse(last_response.body)["session_id"]
raise "FAIL: ask 未返回 session_id" unless new_id

get "/chat/sessions"
list2 = JSON.parse(last_response.body)
entry = list2.find { |s| s["id"] == new_id }
raise "FAIL: 新会话 #{new_id} 未出现在列表" unless entry
raise "FAIL: 新会话 preview 应为空字符串" unless entry["preview"] == ""
puts "PASS: POST /chat/ask 后新会话（id=#{new_id}, title=#{entry['title'].inspect}）出现在列表中"

# 3) DELETE 不存在的 id 返回 404
delete "/chat/sessions/999999999"
raise "FAIL: DELETE 不存在的 id 应返回 404，实际 #{last_response.status}" unless last_response.status == 404
puts "PASS: DELETE /chat/sessions/999999999 -> 404"

# 4) 补充：DELETE 存在的 id 返回 {ok: true} 且消息一并删除
msg_count = Message.where(chat_session_id: new_id).count
delete "/chat/sessions/#{new_id}"
raise "FAIL: DELETE status=#{last_response.status}" unless last_response.status == 200
raise "FAIL: DELETE 未返回 ok:true" unless JSON.parse(last_response.body)["ok"] == true
raise "FAIL: 会话未被删除" if ChatSession.exists?(new_id)
raise "FAIL: 会话消息未级联删除" if Message.where(chat_session_id: new_id).exists?
puts "PASS: DELETE /chat/sessions/#{new_id} -> {ok: true}，#{msg_count} 条消息已级联删除"

puts "\n全部自检通过 ✅"
