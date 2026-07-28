# frozen_string_literal: true

# 造一个 GBK 编码的临时文件，验证编码归一逻辑
gbk_text = "月份,销量（台）\n1月,1500\n2月,1200\n"
raw = gbk_text.encode(Encoding::GBK)
tmp = EnterpriseFileService.root.join("gbk_test_tmp.csv")
File.binwrite(tmp.to_s, raw)

begin
  c = EnterpriseFileService.read("gbk_test_tmp.csv")
  puts "编码: #{c.encoding}"
  puts "内容: #{c}"
  puts "含乱码替换符: #{c.include?("�")}"
  puts(c.include?("销量（台）") ? "GBK 转码成功" : "GBK 转码失败")
ensure
  File.delete(tmp.to_s)
end
