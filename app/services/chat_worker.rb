# frozen_string_literal: true

# 后台执行一次问答：检索注入 -> Kimi 调用 -> 结果落库。
# 由 ChatController#ask 以线程方式异步触发，前端轮询 /chat/history 获取结果。
class ChatWorker
  def self.perform_async(chat_session_id, prompt, ip)
    Thread.new do
      Rails.application.executor.wrap do
        new(chat_session_id, prompt, ip).perform
      end
    end
  end

  def initialize(chat_session_id, prompt, ip)
    @chat_session_id = chat_session_id
    @prompt = prompt
    @ip = ip
  end

  def perform
    # 检索注入：企业文件片段 + company.db 数据样例
    retrieval = EnterpriseRetriever.build_context(@prompt, ip: @ip)
    full_prompt = retrieval[:context].present? ? "#{retrieval[:context]}\n用户问题：#{@prompt}" : @prompt

    ActiveRecord::Base.connection_pool.with_connection do
      chat_session = ChatSession.find(@chat_session_id)

      options = nil
      if chat_session.kimi_session_id.present?
        options = KimiAgentSDK::KimiAgentOptions.new(resume: chat_session.kimi_session_id)
      end

      reply = +""
      kimi_session_id = chat_session.kimi_session_id

      KimiAgentSDK.query(prompt: full_prompt, options: options) do |message|
        case message
        when KimiAgentSDK::AssistantMessage
          reply << message.content.to_s << "\n"
        when KimiAgentSDK::ResultMessage
          kimi_session_id = message.session_id
        end
      end

      chat_session.update!(kimi_session_id: kimi_session_id) if kimi_session_id.present?
      chat_session.messages.create!(
        role: "assistant",
        content: reply.strip,
        sources: retrieval[:sources].to_json
      )

      source_names = retrieval[:sources].map { |s| s[:name] }.join(", ")
      AuditLog.create!(
        action: "ask",
        detail: "prompt=#{@prompt.truncate(200)}; sources=#{source_names.presence || '无'}",
        ip: @ip
      )
    end
  rescue StandardError => e
    # 出错也写入一条消息，前端轮询能看到失败原因
    ActiveRecord::Base.connection_pool.with_connection do
      ChatSession.find(@chat_session_id).messages.create!(
        role: "assistant",
        content: "Kimi 调用失败: #{e.message}",
        sources: [].to_json
      )
    end
  end
end
