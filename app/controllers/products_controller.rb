
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
  	request["Authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJtaWtvbGFqLm1hc3puZXJAZ21haWwuY29tIiwicm9sZSI6InR1cnVtX2N1c3RvbWVyIiwiZXhwIjoxNzQwMTU2MzQwfQ.FbD22P7NJHNkh5On3RJ6XE6EAvPhPLUPUdc7j8_ENH8"
  	request["Accept"] = "application/json"

  	# Perform the HTTP request
  	response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  	  http.request(request)
  	end

  	# Parse and print the response
  	response_body = JSON.parse(response.body)
    # first_product = response_body["data"].first
    # create_shopify_product(first_product)

  	if response_body["data"].present?
  	  response_body["data"].first(1).each do |product_data|
          puts response_body["product_data"]
  	    # create_or_update_shopify_product(product_data, 103901626692)
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
















 def create_or_update_shopify_product(data, location_id)
   begin
     client = ShopifyAPI::Clients::Rest::Admin.new(session: @session)

     # Step 1: Check if the product already exists by searching for its title
     search_response = client.get(path: "products.json", query: { title: data["name"] })

     existing_product = search_response.body["products"].find { |p| p["title"] == data["name"] }

     if existing_product
       product_id = existing_product["id"]
       puts "🔄 Product already exists: #{existing_product['title']} (ID: #{product_id})"
       
       # Step 2: Update variants instead of creating a new product
       update_shopify_variants(client, product_id, data, location_id)
     else
       # Step 3: Create a new product if it does not exist
       create_new_shopify_product(client, data, location_id)
     end

   rescue Errno::ECONNRESET => e
     puts "🔄 Connection reset error: #{e.message}. Retrying..."
     retry
   rescue StandardError => e
     puts "⚠️ Error: #{e.message}"
   end
 end

 # Function to update variants of an existing product
 def update_shopify_variants(client, product_id, data, location_id)
   # Get current variants of the product
   existing_variants_response = client.get(path: "products/#{product_id}.json")
   existing_variants = existing_variants_response.body["product"]["variants"]

   data["variants"].each do |variant|
     existing_variant = existing_variants.find { |v| v["option1"] == variant["size"].to_s }

     if existing_variant
       # If variant exists, update inventory
       update_shopify_inventory(client, existing_variant["inventory_item_id"], location_id, variant["stock"].to_i)
       puts "✅ Updated existing variant: Size #{variant['size']}"
     else
       # If variant does not exist, add a new variant
       new_variant_data = {
         variant: {
           product_id: product_id,
           sku: "#{data['sku']}-#{variant['size']}",
           title: "#{data['name']} - Size #{variant['size']}",
           option1: variant["size"].to_s,
           price: variant["price"].to_f,
           compare_at_price: (variant["price"].to_f * 1.2).round(2),
           inventory_management: "shopify",
           inventory_policy: "continue",
           barcode: "BAR#{variant['variant_id'][0..5]}"
         }
       }
       
       new_variant_response = client.post(path: "variants.json", body: new_variant_data)
       if new_variant_response.code == 201
         new_variant = new_variant_response.body["variant"]
         update_shopify_inventory(client, new_variant["inventory_item_id"], location_id, variant["stock"].to_i)
         puts "✅ Added new variant: Size #{variant['size']}"
       else
         puts "❌ Error adding new variant: #{new_variant_response.body}"
       end
     end
   end
 end

 # Function to create a new product
 def create_new_shopify_product(client, data, location_id)
   product_data = {
     product: {
       title: data["name"],
       body_html: "<strong>Limited Edition Sneakers</strong>",
       vendor: data["brand"],
       product_type: "Shoes",
       tags: "Sneakers,Limited Edition,#{data['brand']}",
       status: "draft",
       images: [{ src: data["image"] }],
       options: [
         {
           name: "Size",
           values: data["variants"].map { |v| v["size"].to_s }
         }
       ],
       variants: data["variants"].map do |variant|
         {
           sku: "#{data['sku']}-#{variant['size']}",
           title: "#{data['name']} - Size #{variant['size']}",
           option1: variant["size"].to_s,
           price: variant["price"].to_f,
           compare_at_price: (variant["price"].to_f * 1.2).round(2),
           inventory_management: "shopify",
           inventory_policy: "continue",
           barcode: "BAR#{variant['variant_id'][0..5]}",
           inventory_quantity: 0
         }
       end
     }
   }

   response = client.post(path: "products.json", body: product_data)

   if response.code == 201
     product_id = response.body["product"]["id"]
     puts "✅ New product created: #{response.body['product']['title']} (ID: #{product_id})"
     response.body["product"]["variants"].each_with_index do |variant, index|
       update_shopify_inventory(client, variant["inventory_item_id"], location_id, data["variants"][index]["stock"].to_i)
     end
   else
     puts "❌ Error creating product: #{response.body}"
   end
 end

 # Function to update inventory levels
 def update_shopify_inventory(client, inventory_item_id, location_id, stock_quantity)
   inventory_data = {
     location_id: location_id,
     inventory_item_id: inventory_item_id,
     available: stock_quantity
   }

   inventory_response = client.post(path: "inventory_levels/set.json", body: inventory_data)

   if inventory_response.code == 200
     puts "✅ Inventory updated for Inventory Item #{inventory_item_id} (Stock: #{stock_quantity}) at Location #{location_id}"
   else
     puts "❌ Error updating inventory: #{inventory_response.body}"
   end
 end



  def check_all_feed_brand
    uri = URI("https://api.b2b.turum.pl/v1/products_full_list")

    # Set up the request
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJtaWtvbGFqLm1hc3puZXJAZ21haWwuY29tIiwicm9sZSI6InR1cnVtX2N1c3RvbWVyIiwiZXhwIjoxNzQwMTU2MzQwfQ.FbD22P7NJHNkh5On3RJ6XE6EAvPhPLUPUdc7j8_ENH8"
    request["Accept"] = "application/json"

    # Perform the HTTP request
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    # Parse the response
    response_body = JSON.parse(response.body)

    if response_body["data"].present?
      # Extract unique brands
      unique_brands = response_body["data"].map { |product| product["brand"] }.uniq

      # Write unique brands to a text file
      File.open("unique_brands.txt", "w") do |file|
        unique_brands.each { |brand| file.puts(brand) }
      end

      puts "✅ Unique brands saved to unique_brands.txt!"
    else
      puts "No products found in the API response."
    end
  end










  def remove_extra_shopify_product
    begin
      puts "🔄 Fetching external product feed..."
      
      # Fetch external products
      uri = URI("https://api.b2b.turum.pl/v1/products_full_list")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{ENV['TURUM_API_KEY']}"
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      external_data = JSON.parse(response.body)

      unless external_data["data"]
        puts "⚠️ No products found in vendor API. Exiting..."
        return
      end

      # Extract SKUs from external API
      external_skus = external_data["data"].map { |product| product["sku"] }.compact
      puts "✅ Found #{external_skus.count} products in the external feed."

      # Vendors whose products should be checked & removed if missing
      target_vendors = ["ASICS", "CROCS", "PUMA", "AIR JORDAN", "ON", "NIKE", "ADIDAS", "NEW BALANCE", "VANS"]

      # Fetch all Shopify products with pagination
      all_shopify_products = fetch_all_shopify_products
      puts "✅ Fetched #{all_shopify_products.count} products from Shopify."

      # Identify Shopify products not in the external feed
      products_to_remove = []

      all_shopify_products.each do |product|
        # Check if product belongs to the target vendors
        next unless target_vendors.include?(product["vendor"])

        # Extract SKUs from product variants
        product_skus = product["variants"].map { |variant| variant["sku"] }.compact

        # If none of the product's SKUs exist in the external feed, mark for deletion
        unless product_skus.any? { |sku| external_skus.include?(sku) }
          products_to_remove << { id: product["id"], title: product["title"], vendor: product["vendor"] }
        end
      end

      puts "🚨 Found #{products_to_remove.count} extra products from target vendors to remove."

      # Remove products from Shopify
      products_to_remove.each do |product|
        delete_shopify_product(product[:id])
        puts "🗑 Removed: #{product[:title]} (Vendor: #{product[:vendor]})"
      end

      puts "✅ Cleanup completed successfully!"

    rescue JSON::ParserError => e
      puts "❌ Error parsing vendor API response: #{e.message}"
    rescue Errno::ECONNRESET, Net::OpenTimeout => e
      puts "🔄 Connection error: #{e.message}. Retrying..."
      retry
    rescue StandardError => e
      puts "⚠️ Unexpected error: #{e.message}"
    end
  end

  def fetch_all_shopify_products
    client = ShopifyAPI::Clients::Rest::Admin.new(session: @session)
    products = []
    next_page_info = nil

    loop do
      query_params = { "fields" => "id,title,vendor,variants", "limit" => 250 }
      query_params["page_info"] = next_page_info if next_page_info

      response = client.get(path: "products.json", query: query_params)

      if response.code == 200
        body = response.body
        products.concat(body["products"])
        next_page_info = extract_next_page_info(response)

        break unless next_page_info # Stop if no more pages
      else
        puts "❌ Error fetching Shopify products: #{response.body}"
        break
      end
    end

    products
  end

  def extract_next_page_info(response)
    link_header = response.headers["link"]
    return nil unless link_header

    # Extract "next" page_info from Shopify's pagination header
    match = link_header.match(/page_info=([^&>]+).*rel="next"/)
    match[1] if match
  end

  def delete_shopify_product(product_id)
    client = ShopifyAPI::Clients::Rest::Admin.new(session: @session)
    response = client.delete(path: "products/#{product_id}.json")

    if response.code == 200
      puts "✅ Successfully deleted product ID: #{product_id}"
    else
      puts "❌ Failed to delete product ID: #{product_id}, Error: #{response.body}"
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

