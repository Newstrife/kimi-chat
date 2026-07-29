# frozen_string_literal: true

queries = [
  "品牌一部的考勤规则和总部一样吗",   # 应命中 2 个考勤文件，可能还有员工手册
  "分析2026年全年的销售情况",          # 主要命中销售 CSV
  "年假有几天？",                      # 员工手册 + 考勤规程
  "产品价格和库存",                    # 价目表
  "差旅报销住宿标准",                  # 员工手册
  "今天天气怎么样"                     # 应无文件入选（阈值过滤）
]

queries.each do |q|
  built = EnterpriseRetriever.build_context(q)
  files = built[:sources].select { |s| s[:type] == "file" }.map { |s| s[:name] }
  puts "#{q}"
  puts "  入选 #{files.size} 个文件: #{files.inspect}"
end
