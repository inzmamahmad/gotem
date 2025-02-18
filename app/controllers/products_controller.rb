
require 'uri'
require 'net/http'
require 'tempfile'
# require 'roo'
# require 'net/http'
# require 'uri'
require 'json'

class ProductsController < ApplicationController
  before_action :shopify_session, only: %i[index ]
  def index

  	uri = URI("https://api.b2b.turum.pl/v1/products?page=1&page_size=50&search_query=nike")

  	# Set up the request
  	request = Net::HTTP::Get.new(uri)
  	request["Authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJtaWtvbGFqLm1hc3puZXJAZ21haWwuY29tIiwicm9sZSI6InR1cnVtX2N1c3RvbWVyIiwiZXhwIjoxNzM5OTczNDU2fQ.iofruD3D42-TvpD_Foqj6YzgyFRj19Lo6ZA66Rf6uaU"
  	request["Accept"] = "application/json"

  	# Perform the HTTP request
  	response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  	  http.request(request)
  	end

  	# Parse and print the response
  	response_body = JSON.parse(response.body)


  	if response_body["data"].present?
  	  response_body["data"].first(10).each do |product_data|

  	    create_shopify_product(product_data)
  	  end
  	else
  	  puts "No products found in the API response."
  	end
  	
  	puts response_body
  	render json:response_body
 
    # create_shopify_product(first_product)
  end


  def create_shopify_product(data)
    begin
      # Convert stock to integer (removes `+` if present)
      inventory_quantity = data["stock"].gsub("+", "").to_i

      product_data = {
        product: {
          title: data["name"],           # "Nike Dunk Low Grey Fog"
          body_html: "<strong>Limited Edition Sneakers</strong>",
          vendor: "Nike",                # Static vendor (update if needed)
          product_type: "Shoes",         # Static product type (update if needed)
          status: "active",
          images: [{ src: data["image"] }],  # Image URL from data
          variants: [{
            sku: data["sku"],                 # SKU from data
            price: data["price"].to_f,        # Convert price to float
            inventory_management: "shopify",
            inventory_quantity: inventory_quantity
          }]
        }
      }

      # Send request to Shopify API
      client = ShopifyAPI::Clients::Rest::Admin.new(session: @session)
      response = client.post(path: "products.json", body: product_data)

      if response.code == 201
        puts "✅ Product created: #{response.body['product']['title']}"
      else
        puts "❌ Error creating product: #{response.body}"
      end

    rescue Errno::ECONNRESET => e
      puts "🔄 Connection reset error: #{e.message}. Retrying..."
      retry
    rescue StandardError => e
      puts "⚠️ Error: #{e.message}"
    end
  end




  private

    def shopify_session
      @session = ShopifyAPI::Auth::Session.new(
        shop: ENV['SHOPIFY_SHOP'],
        access_token: ENV['SHOPIFY_ACCESS_TOKEN'],
      )
    end
end

