
require 'uri'
require 'net/http'
require 'tempfile'
require 'json'

class ProductsController < ApplicationController
  before_action :shopify_session, only: %i[index sync_vendor_stock]
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
  	  response_body["data"].first(1).each do |product_data|

  	    # create_shopify_product(product_data)
  	  end
  	else
  	  puts "No products found in the API response."
  	end
  	
  	puts response_body
  	render json:response_body
  end

  def sync_vendor_stock
    begin
      puts "🔄 Syncing vendor stock..."

      # 1️⃣ Fetch vendor stock data
      uri = URI("https://api.b2b.turum.pl/v1/products?page=1&page_size=50&search_query=nike")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJtaWtvbGFqLm1hc3puZXJAZ21haWwuY29tIiwicm9sZSI6InR1cnVtX2N1c3RvbWVyIiwiZXhwIjoxNzM5OTczNDU2fQ.iofruD3D42-TvpD_Foqj6YzgyFRj19Lo6ZA66Rf6uaU"
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      vendor_data = JSON.parse(response.body)

      # 2️⃣ Check if data exists
      if vendor_data["data"].nil? || vendor_data["data"].empty?
        puts "⚠️ No products found in vendor API. Exiting sync..."
        return
      end

      puts "✅ Found #{vendor_data['data'].size} products. Processing first 10..."

      # 3️⃣ Loop through first 10 products
      vendor_data["data"].first(10).each do |item|
        sku = item["sku"]
        stock_quantity = item["stock"].to_s.gsub("+", "").to_i # Convert stock to integer
        puts "🔍 Searching Shopify for SKU: #{stock_quantity}..."
        puts "🔍 Searching Shopify for SKU: #{sku}..."

        # 4️⃣ Find Shopify variant using SKU
        variant = find_shopify_variant_by_sku(sku)
        if variant.nil?
          puts "⚠️ SKU #{sku} not found in Shopify, skipping..."
          next
        end

        # 5️⃣ Update inventory levels in Shopify
        update_inventory_quantity(variant["inventory_item_id"], stock_quantity)
      end

      puts "✅ Stock sync completed successfully!"

    rescue JSON::ParserError => e
      puts "❌ Error parsing vendor API response: #{e.message}"
    rescue Errno::ECONNRESET, Net::OpenTimeout => e
      puts "🔄 Connection error: #{e.message}. Retrying..."
      retry
    rescue StandardError => e
      puts "⚠️ Unexpected error: #{e.message}"
    end
  end






  def find_shopify_variant_by_sku(sku)
    client = ShopifyAPI::Clients::Rest::Admin.new(session: @session)
    
    response = client.get(path: "products.json", query: { "fields" => "id,title,variants", "limit" => 250 })
    
    if response.code == 200
      products = response.body["products"]

      products.each do |product|
        variant = product["variants"].find { |v| v["sku"] == sku }
        # debugger
        return variant if variant
      end
    else
      puts "❌ Error fetching Shopify variants: #{response.body}"
    end

    nil
  end

 









 def update_inventory_quantity(inventory_item_id, quantity)
   inventory_data = {
     location_id: ENV['SHOPIFY_LOCATION_ID'], # Your Shopify Location ID
     inventory_item_id: inventory_item_id,
     available: quantity
   }

   client = ShopifyAPI::Clients::Rest::Admin.new(session: @session)
   response = client.post(path: "inventory_levels/set.json", body: inventory_data)

   if response.code == 200
     puts "✅ Inventory updated: Item #{inventory_item_id} → #{quantity} units"
   else
     puts "❌ Error updating inventory: #{response.body}"
   end
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

