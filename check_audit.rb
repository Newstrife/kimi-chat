# frozen_string_literal: true

puts "ChatSession: #{ChatSession.count}"
puts "Message: #{Message.count}"
puts "AuditLog 最近 10 条:"
AuditLog.order(id: :desc).limit(10).reverse_each do |a|
  puts "  [#{a.action}] #{a.detail.to_s.truncate(80)} (ip: #{a.ip})"
end
