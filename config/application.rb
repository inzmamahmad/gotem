require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Gotem
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
  end



 # Replace with actual values or set these from environment variables
 ShopifyAPI::Context.setup(
   api_key: ENV['SHOPIFY_API_KEY'],                    # Set your Shopify API key here
   api_secret_key: ENV['SHOPIFY_API_SECRET_KEY'],      # Set your API secret key here
   host_name: ENV['SHOPIFY_SHOP'],                     # Set your Shopify shop domain here
   scope: "read_orders,read_products",                 # Adjust the scope as needed
   is_embedded: false,                                # Set based on whether it's an embedded app
   api_version: '2022-07',                             # Set a valid API version
   is_private: false,                                  
   session_storage: ShopifyAPI::Auth::FileSessionStorage.new  # Use a file-based session storage
 )

end
