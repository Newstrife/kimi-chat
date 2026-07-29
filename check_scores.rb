# frozen_string_literal: true

q = "品牌一部的考勤规则和总部一样吗"
tokens = q.scan(/\p{Han}+|[a-zA-Z0-9_]+/).flat_map do |seg|
  if seg.match?(/\A\p{Han}+\z/)
    next [] if seg.length < 2

    seg.length >= 3 ? seg.chars.each_cons(2).map(&:join) : [seg]
  else
    seg.length >= 2 ? [seg] : []
  end
end.uniq

EnterpriseFileService.list.each do |rel_path|
  next unless %w[.md .txt .csv .json .log].include?(File.extname(rel_path).downcase)

  c = EnterpriseFileService.read(rel_path)
  content_score = tokens.sum { |t| [c.scan(Regexp.escape(t)).size, 10].min }
  name_score = tokens.sum { |t| rel_path.scan(Regexp.escape(t)).size } * 3
  puts "#{rel_path}: content=#{content_score} name=#{name_score} total=#{content_score + name_score}"
end
