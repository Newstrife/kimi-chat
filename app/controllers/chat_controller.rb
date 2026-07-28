# frozen_string_literal: true

# 简单聊天界面 + 多轮对话接口（异步版）。
#
# 前端页面：GET /
# 提交问题：POST /chat/ask  {prompt, session_id?} -> {session_id, status: "processing"}
#   立即返回，后台线程执行检索 + Kimi 调用，结果写入 messages 表
# 轮询历史：GET /chat/history?session_id= -> {session_id, title, messages}
#   前端通过轮询此接口获取回答，避免长时间等待导致浏览器网络错误
class ChatController < ApplicationController
  # 问答接口为 JSON API，不带 session cookie，跳过 CSRF 校验（页面 JS 会带 token，curl 则免验）
  skip_forgery_protection only: :ask

  def index
  end

  def ask
    prompt = params[:prompt].to_s.strip
    return render json: { error: "prompt 不能为空" }, status: :bad_request if prompt.empty?

    chat_session = ChatSession.find_by(id: params[:session_id]) if params[:session_id].present?
    chat_session ||= ChatSession.create!(title: prompt.truncate(30))
    chat_session.messages.create!(role: "user", content: prompt)

    ChatWorker.perform_async(chat_session.id, prompt, request.remote_ip)

    render json: { session_id: chat_session.id, status: "processing" }
  end

  def history
    chat_session = ChatSession.includes(:messages).find_by(id: params[:session_id])
    return render json: { error: "会话不存在" }, status: :not_found unless chat_session

    render json: {
      session_id: chat_session.id,
      title: chat_session.title,
      messages: chat_session.messages.order(:created_at, :id).map do |m|
        { role: m.role, content: m.content, sources: m.sources.present? ? JSON.parse(m.sources) : [] }
      end
    }
  end
end
