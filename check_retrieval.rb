# frozen_string_literal: true

queries = [
  "分析2026年全年的销售情况",
  "品牌一部的考勤规则和总部一样吗",
  "年假有几天？",
  "Q2 会议纪要的营收是多少"
]

queries.each do |q|
  built = EnterpriseRetriever.build_context(q)
  files = built[:sources].select { |s| s[:type] == "file" }.map { |s| s[:name] }
  dbs = built[:sources].select { |s| s[:type] == "database" }.map { |s| s[:name] }
  puts "#{q} => files=#{files.inspect} db=#{dbs.inspect}"
end
