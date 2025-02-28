Rails.application.routes.draw do




  resources :products do
    collection do
      get :sync_vendor_stock
      get :check_all_feed_brand
      get :remove_extra_shopify_product
      get :fetch_all_shopify_products
      get :delete_shopify_product
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  
  # Defines the root path route ("/")
  root "products#index"
end
