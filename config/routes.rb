Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

  # 聊天界面首页与问答接口
  root "chat#index"
  post "chat/ask", to: "chat#ask"
  get "chat/history", to: "chat#history"
  get "chat/sessions", to: "chat#sessions"
  delete "chat/sessions/:id", to: "chat#destroy_session"

  # 企业数据库数据源只读管理页
  get "databases", to: "databases#index"
  get "databases/test", to: "databases#test"
end
