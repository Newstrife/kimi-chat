# frozen_string_literal: true

# 验证：命中文件是否注入完整内容（而非 1500 字符截断）
built = EnterpriseRetriever.build_context("分析2026年全年的销售情况")
ctx = built[:context]

puts "context 总长度: #{ctx.length} 字符"
puts "CSV 12 月数据是否完整包含（检查 12 月 330 万）: #{ctx.include?("2026年12月,330")}"
puts "是否标注完整内容: #{ctx.include?("（完整内容）")}"

# 大文件（百瑞吉总部考勤规程.txt 35KB）应标注截断
built2 = EnterpriseRetriever.build_context("品牌一部的考勤规则和总部一样吗")
puts "大文件是否标注截断: #{built2[:context].include?("非完整内容")}"
