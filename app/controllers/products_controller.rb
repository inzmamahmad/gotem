
require 'uri'
require 'net/http'
require 'tempfile'
require 'json'

class ProductsController < ApplicationController
  before_action :shopify_session, only: %i[index sync_vendor_stock]
  def index

  	uri = URI("https://api.b2b.turum.pl/v1/products_full_list")

  	# Set up the request
  	request = Net::HTTP::Get.new(uri)
  	request["Authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJtaWtvbGFqLm1hc3puZXJAZ21haWwuY29tIiwicm9sZSI6InR1cnVtX2N1c3RvbWVyIiwiZXhwIjoxNzQwMDY5MTEzfQ.JXvHR3RfJ36CwzvL7NMsZbanMpkoEDFhZY0-kX9JqJs"
  	request["Accept"] = "application/json"

  	# Perform the HTTP request
  	response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  	  http.request(request)
  	end

  	# Parse and print the response
  	response_body = JSON.parse(response.body)
    first_product = response_body["data"].first
    # create_shopify_product(first_product)

  	if response_body["data"].present?
  	  response_body["data"].first(10).each do |product_data|
          puts response_body["product_data"]
  	    create_shopify_product(product_data)
  	  end
  	else
  	  puts "No products found in the API response."
  	end
  	
  	puts response_body["data"].first
  	render json:response_body["data"].first
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
     # Prepare Shopify product payload
     product_data = {
       product: {
         title: data["name"],  # Product name
         body_html: "<strong>Limited Edition Sneakers</strong>",  # Product description
         vendor: data["brand"],  # Dynamic vendor (brand)
         product_type: "Shoes",  # Product category
         tags: "Sneakers,Limited Edition,#{data['brand']}",  # Dynamic tagging
         status: "active",
         images: [{ src: data["image"] }],  # Product image

         # ✅ Corrected `options` format
         options: [
           {
             name: "Size", 
             values: data["variants"].map { |v| v["size"].to_s } # Ensure sizes are strings
           }
         ],

         # Variants setup
         variants: data["variants"].map do |variant|
           {
             sku: "#{data['sku']}-#{variant['size']}",  # Unique SKU per variant
             title: "#{data['name']} - Size #{variant['size']}",  # Variant title
             option1: variant["size"].to_s,  # Size must be a string
             price: variant["price"].to_f,  # Convert price to float
             compare_at_price: (variant["price"].to_f * 1.2).round(2),  # 20% markup
             inventory_management: "shopify",
             inventory_quantity: variant["stock"].to_i,  # Convert stock to integer
             inventory_policy: "continue",  # Allows overselling if stock reaches zero
             barcode: "BAR#{variant['variant_id'][0..5]}",  # Generate fake barcode
           }
         end
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

