# frozen_string_literal: true

# 企业数据检索注入：
# 对用户 prompt 做简单关键词检索，取匹配度最高的前 2 个企业文件片段
# （各截取 1500 字符），加上所有 enabled 数据库数据源的表结构和数据样例，
# 拼成企业数据上下文。
class EnterpriseRetriever
  MAX_FILES = 2
  SNIPPET_CHARS = 1500
  TEXT_EXTENSIONS = %w[.md .txt .csv .json .log].freeze

  # 返回 { context: String, sources: [{ type:, name: }] }
  def self.build_context(prompt, ip: nil)
    # 分词：把 prompt 切成"纯中文段"和"字母数字段"，3 字以上的中文段再切成二元组。
    # 避免"分析2026年全年的销售情况"这种中文数字连写的整句被当成一个无法命中的长词
    tokens = prompt.to_s.scan(/\p{Han}+|[a-zA-Z0-9_]+/).flat_map do |seg|
      if seg.match?(/\A\p{Han}+\z/)
        next [] if seg.length < 2 # 单字中文噪声太大，丢弃

        seg.length >= 3 ? seg.chars.each_cons(2).map(&:join) : [seg]
      else
        seg.length >= 2 ? [seg] : []
      end
    end.uniq

    scored = []
    EnterpriseFileService.list.each do |rel_path|
      next unless TEXT_EXTENSIONS.include?(File.extname(rel_path).downcase)

      content = EnterpriseFileService.read(rel_path, ip: ip)
      # 评分 = 内容命中 + 文件名命中 x3（文件名往往是信息密度最高的部分，
      # 例如"2026年销售情况.csv"的关键词全在文件名里）
      score = tokens.sum { |t| content.scan(Regexp.escape(t)).size } +
              tokens.sum { |t| rel_path.scan(Regexp.escape(t)).size } * 3
      scored << [score, rel_path, content] if score.positive?
    end

    top = scored.sort_by { |score, _rel, _content| -score }.first(MAX_FILES)

    parts = top.map do |_score, rel_path, content|
      "【企业文件：#{rel_path}】\n#{content[0, SNIPPET_CHARS]}"
    end
    sources = top.map { |_score, rel_path, _content| { type: "file", name: rel_path } }

    database_summaries(ip: ip).each do |summary|
      parts << "【企业数据库 #{summary[:label]}（表结构 + 每表前 #{summary[:sample_rows]} 行数据）】\n#{summary[:text]}"
      sources << { type: "database", name: summary[:label] }
    end

    context = <<~TXT
      以下是从企业内部文件和数据库中检索到的相关数据。请只依据这些数据回答用户问题，不要再使用你自己的工具去查找文件或数据库（它们保存在企业内网的安全存储中，你的工具访问不到）。回答时请注明你引用的数据来源（文件名或数据库表）。如果以下数据不足以回答问题，请直接说明还缺什么数据，不要编造。当用户要求画图、趋势、对比图表，或数据天然适合可视化时，请在回答末尾附加一个 ```chart 代码块，内容为合法 JSON，格式：{"type":"bar|line|pie","title":"图表标题","labels":["标签1","标签2"],"series":[{"name":"系列名","data":[1,2]}]}；bar/line 可多组 series，pie 只用一组 series；chart 块内只输出 JSON 不要其他文字。

      #{parts.join("\n\n")}
    TXT

    { context: context, sources: sources }
  rescue StandardError
    # 检索失败不阻塞正常聊天，降级为无上下文
    { context: "", sources: [] }
  end

  # 遍历所有 enabled 数据源，返回 [{ label:, text:, sample_rows: }]。
  # 单个源失败（连接不上/缺 gem）不影响其他源，跳过即可。
  def self.database_summaries(ip: nil)
    EnterpriseQueryService.sources.filter_map do |source|
      summary = database_summary(source: source[:name], ip: ip)
      next if summary.blank?

      cfg = EnterpriseQueryService.source_config(source[:name])
      { label: "#{source[:name]} (#{source[:adapter]})", text: summary,
        sample_rows: EnterpriseQueryService.sample_rows(cfg) }
    end
  end

  # 单个数据源每张表的结构 + 前 sample_rows 行数据样例
  def self.database_summary(source: :company, ip: nil)
    cfg = EnterpriseQueryService.source_config(source)
    sample_rows = EnterpriseQueryService.sample_rows(cfg)

    EnterpriseQueryService.tables(source: source, ip: ip).map do |table|
      sample = EnterpriseQueryService.query("SELECT * FROM #{table}", source: source, ip: ip)
      rows = sample[:rows].first(sample_rows)
      lines = rows.map do |row|
        sample[:columns].zip(row).map { |col, val| "#{col}=#{val}" }.join(", ")
      end
      "#{table}（#{sample[:columns].join(', ')}）：\n#{lines.join("\n")}"
    end.join("\n\n")
  rescue StandardError
    nil
  end
end
