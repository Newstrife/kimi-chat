class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # HTTP Basic 认证：用户名密码读 ENV，未设置时默认 admin / admin123
  http_basic_authenticate_with(
    name: ENV.fetch("KIMI_CHAT_USER", "admin"),
    password: ENV.fetch("KIMI_CHAT_PASSWORD", "admin123")
  )
end
