# frozen_string_literal: true

c = EnterpriseFileService.read("2026年销售情况.csv")
puts "编码: #{c.encoding}"
puts "前 120 字符: #{c[0, 120]}"
puts "含乱码替换符: #{c.include?("�")}"
