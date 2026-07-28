# frozen_string_literal: true

require "pathname"

# 企业文件服务：只读访问企业数据根目录下的文件。
# - 根目录默认 E:/brjaiagent/enterprise_data，可用 ENV["ENTERPRISE_DATA_DIR"] 覆盖
# - 防目录穿越：展开后的绝对路径必须位于根目录之内
# - 单文件最多读取 20KB
class EnterpriseFileService
  MAX_BYTES = 20 * 1024

  class Error < StandardError; end

  def self.root
    Pathname.new(ENV["ENTERPRISE_DATA_DIR"] || "E:/brjaiagent/enterprise_data").expand_path
  end

  # 返回根目录下所有文件的相对路径列表
  def self.list
    return [] unless root.directory?

    Dir.glob(root.join("**", "*").to_s)
       .select { |f| File.file?(f) }
       .map { |f| Pathname.new(f).relative_path_from(root).to_s }
       .sort
  end

  # 读取相对路径对应的文件内容（最多 20KB），并写入审计日志
  def self.read(rel_path, ip: nil)
    path = root.join(rel_path.to_s).expand_path

    # 防目录穿越：展开后必须仍在根目录内（Windows 路径不区分大小写）
    unless path.to_s.downcase.start_with?(root.to_s.downcase + File::SEPARATOR)
      raise Error, "非法路径（目录穿越）: #{rel_path}"
    end
    raise Error, "文件不存在: #{rel_path}" unless path.file?

    # 按字节读取后做编码归一：优先 UTF-8；不是合法 UTF-8 时按 GBK 转码
    # （国内企业环境常见 GBK/GB2312 编码的 Excel 导出文件），避免中文变乱码
    raw = File.binread(path.to_s, MAX_BYTES)
    content = raw.dup.force_encoding(Encoding::UTF_8)
    unless content.valid_encoding?
      content = raw.dup.force_encoding(Encoding::GBK)
                   .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
    content = content.scrub

    AuditLog.create!(action: "file_read", detail: rel_path.to_s, ip: ip)

    content
  end
end
