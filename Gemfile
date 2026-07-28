source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Local Kimi Agent SDK (kimi CLI 的 Ruby 封装)
gem "kimi-agent-sdk", path: "../kimi-agent-sdk-ruby"

# 企业数据库适配器（按需在下方取消注释并 bundle install）：
# gem "pg", require: false        # PostgreSQL
# gem "mysql2", require: false    # MySQL
# gem "tiny_tds", require: false  # SQL Server

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
end
