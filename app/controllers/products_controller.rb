
require 'uri'
require 'net/http'
require 'tempfile'
require 'json'
require 'shopify_api'
class ProductsController < ApplicationController
  # before_action :shopify_session, only: %i[index sync_vendor_stock fetch_all_shopify_products]
    before_action :shopify_session
    VENDORS = ["ASICS", "ADIDAS", "NIKE", "NEW BALANCE", "AIR JORDAN", "ON", "CROCS", "PUMA", "VANS"]

    def index
      # @products = []
      # total_count = 0
        products = ShopifyAPI::Product.all(session: @session)

      # VENDORS.each do |vendor|
      #   products = ShopifyAPI::Product.all(session: @session, vendor: vendor)
      #   count = ShopifyAPI::Product.count(session: @session, vendor: vendor).body['count']

      #   puts "Vendor: #{vendor}, Count: #{count}"
      #   total_count += count if count
      #   @products.concat(products) if products.present?
      # end

      # puts "Total Products Count: #{total_count}"
      
      if products.present?
        render json: @products
      else
        render json: { message: "No products found" }, status: :not_found
      end
    end


  def fetch_api_data
     puts "befor remove extra products"
      remove_extra_shopify_product
    puts "After remove extra products"
      # Usage:
      api_key = authenticate("mikolaj.maszner@gmail.com", "Mikiziom4.")

      puts "Stored API Key: #{api_key}" if api_key

    uri = URI("https://api.b2b.turum.pl/v1/products_full_list")

    # Set up the request
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{api_key}"
    request["Accept"] = "application/json"

    # Perform the HTTP request
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    # Parse and print the response
    response_body = JSON.parse(response.body)
    # first_product = response_body["data"].first
    # create_shopify_product(first_product)
    total_products = response_body["data"].count
    puts "total products: #{total_products}"
    if response_body["data"].present?
      response_body["data"].each do |product_data|
          puts response_body["product_data"]
        create_or_update_shopify_product(product_data, 103901626692)
      end
    else
      puts "No products found in the API response."
    end
    

    puts response_body["data"].first
    render json:response_body["data"].first
  end
  def authenticate(username, password)
    base_url = "https://api.b2b.turum.pl/v1"
    uri = URI("#{base_url}/account/login")
    request = Net::HTTP::Post.new(uri, { "Content-Type" => "application/json", "Accept" => "application/json" })

    request.body = { "username" => username, "password" => password }.to_json

    response = send_request(uri, request)

    if response.is_a?(Net::HTTPSuccess)
      json_response = JSON.parse(response.body)
      api_key = json_response["access_token"]  # Adjust if API returns a different key name
      puts "Authenticated successfully. API Key: #{api_key}"
      api_key
    else
      puts "Authentication failed: #{response.body}"
      nil
    end
  end

  def send_request(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.request(request)
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

     # Step 1: Search for existing product by title
     search_response = client.get(
       path: "/admin/api/2025-01/products.json",  # Updated API endpoint
       query: { title: data["name"] }
     )

     existing_product = search_response.body["products"]&.find { |p| p["title"] == data["name"] }

     if existing_product
       product_id = existing_product["id"]
       puts "🔄 Product already exists: #{existing_product['title']} (ID: #{product_id})"

       # Step 2: Update existing product variants
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
 # def update_shopify_variants(client, product_id, data, location_id)
  
 #   # ✅ Use correct API version


 #   existing_variants_response = client.get(path: "/admin/api/2025-01/products/#{product_id}.json")

 #   # existing_variants_response = client.get(path: "/admin/api/2025-01/products/#{product_id}.json")
   
 #   # if existing_variants_response.code != 200
 #   #   puts "❌ Failed to fetch existing variants: #{existing_variants_response.body}"
 #   #   return
 #   # end

 #   existing_variants = existing_variants_response.body.dig("product", "variants") || []

 #   data["variants"].each do |variant|
 #     existing_variant = existing_variants.find { |v| v["option1"] == variant["size"].to_s }

 #     if existing_variant
 #       # ✅ Update existing inventory
 #       update_shopify_inventory(client, existing_variant["inventory_item_id"], location_id, variant["stock"].to_i)
 #       puts "✅ Updated existing variant: Size #{variant['size']}"
 #     else
 #       # ✅ Correct way to add a new variant (update product with new variant)
 #       new_variant_data = {
 #         product: {
 #           id: product_id,
 #           variants: [
 #             {
 #               sku: "#{data['sku']}-#{variant['size']}",
 #               title: "#{data['name']} - Size #{variant['size']}",
 #               option1: variant["size"].to_s,
 #               price: variant["price"].to_f,
 #               compare_at_price: (variant["price"].to_f * 1.2).round(2),
 #               inventory_management: "shopify",
 #               inventory_policy: "continue",
 #               barcode: "BAR#{variant['variant_id'][0..5]}"
 #             }
 #           ]
 #         }
 #       }

 #       new_variant_response = client.put(path: "/admin/api/2024-01/products/#{product_id}.json", body: new_variant_data)

 #       if new_variant_response.code == 200
 #         new_variant = new_variant_response.body.dig("product", "variants")&.last
 #         update_shopify_inventory(client, new_variant["inventory_item_id"], location_id, variant["stock"].to_i) if new_variant
 #         puts "✅ Added new variant: Size #{variant['size']}"
 #       else
 #         puts "❌ Error adding new variant: #{new_variant_response.body}"
 #       end
 #     end
 #   end
 # end

 def update_shopify_variants(client, product_id, data, location_id)
   # ✅ Fetch existing variants from Shopify
   existing_variants_response = client.get(path: "/admin/api/2025-01/products/#{product_id}.json")

   if existing_variants_response.code != 200
     puts "❌ Failed to fetch existing variants: #{existing_variants_response.body}"
     return
   end

   existing_variants = existing_variants_response.body.dig("product", "variants") || []

   # ✅ Extract sizes from provided data
   provided_sizes = data["variants"].map { |v| v["size"].to_s }

   # ✅ Loop through existing Shopify variants
   existing_variants.each do |variant|
     size = variant["option1"].to_s

     # 🛑 If variant exists in Shopify but NOT in data, DELETE it
     unless provided_sizes.include?(size)
       delete_response = client.delete(path: "/admin/api/2025-01/products/#{product_id}/variants/#{variant['id']}.json")

       if delete_response.code == 200
         puts "🗑️ Deleted variant: Size #{size}"
       else
         puts "❌ Error deleting variant #{size}: #{delete_response.body}"
       end
     end
   end

   # ✅ Process new and existing variants
   data["variants"].each do |variant|
     existing_variant = existing_variants.find { |v| v["option1"] == variant["size"].to_s }

     if existing_variant
       # ✅ Update existing variant inventory
       update_shopify_inventory(client, existing_variant["inventory_item_id"], location_id, variant["stock"].to_i)
       puts "✅ Updated existing variant: Size #{variant['size']}"
     else
       # ✅ Add new variant
       new_variant_data = {
         product: {
           id: product_id,
           variants: [
             {
               sku: "#{data['sku']}-#{variant['size']}",
               title: "#{data['name']} - Size #{variant['size']}",
               option1: variant["size"].to_s,
               price: variant["price"].to_f,
               compare_at_price: (variant["price"].to_f * 1.2).round(2),
               inventory_management: "shopify",
               inventory_policy: "continue",
               barcode: "BAR#{variant['variant_id'][0..5]}"
             }
           ]
         }
       }

       new_variant_response = client.put(path: "/admin/api/2025-01/products/#{product_id}.json", body: new_variant_data)

       if new_variant_response.code == 200
         new_variant = new_variant_response.body.dig("product", "variants")&.last
         update_shopify_inventory(client, new_variant["inventory_item_id"], location_id, variant["stock"].to_i) if new_variant
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
     inventory_item_id: inventory_item_id,
     location_id: location_id,
     available: stock_quantity
   }

   puts "🔄 Updating Inventory - Item: #{inventory_item_id}, Location: #{location_id}, Stock: #{stock_quantity}"
    # binding.pry  # Debugging
   inventory_response = client.post(
     path: "/admin/api/2024-04/inventory_levels/set.json", # Use latest stable API version
     body: inventory_data
   )
   if inventory_response.code == 200
     puts "✅ Inventory updated successfully for Item #{inventory_item_id} (Stock: #{stock_quantity})"
   else
     puts "❌ Error updating inventory: #{inventory_response.body}"
   end
 end





 



def check_all_feed_brand
  uri = URI("https://api.b2b.turum.pl/v1/products_full_list")

  # Set up the request
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJtaWtvbGFqLm1hc3puZXJAZ21haWwuY29tIiwicm9sZSI6InR1cnVtX2N1c3RvbWVyIiwiZXhwIjoxNzQwNjYzOTYyfQ.pRC9xqtLNwERTnhtdYYBTSMDrxIxtFHsrCPTybS5ORk"
  request["Accept"] = "application/json"

  # Perform the HTTP request
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  # Parse the response
  response_body = JSON.parse(response.body)

  if response_body["data"].present?
    file_path = "brands_and_titles.txt"

    # Open file for writing
    File.open(file_path, "w") do |file|
      # Group products by brand
      grouped_products = response_body["data"].group_by { |product| product["brand"] || "Unknown Brand" }

      # Write each brand and its products
      grouped_products.each do |brand, products|
        file.puts("Brand: #{brand}")

        products.each do |product|
          title = product["name"] || "Unknown Product Name"
          file.puts("  - #{title}")
        end

        file.puts("\n") # Add spacing between brands
      end
    end

    puts "✅ Brands and product names saved to #{file_path}!"
  else
    puts "❌ No products found in the API response."
  end
end




  def remove_extra_shopify_product
    begin
      puts "🔄 Fetching external product feed..."
      api_key = authenticate("mikolaj.maszner@gmail.com", "Mikiziom4.")

      puts "Stored API Key: #{api_key}" if api_key
      # Fetch external products
      uri = URI("https://api.b2b.turum.pl/v1/products_full_list")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      external_data = JSON.parse(response.body)
      puts "✅ Found #{external_data.count} products in the external feed."
      unless external_data["data"]
        puts "⚠️ No products found in vendor API. Exiting..."
        return
      end

      # ✅ Extract product titles from external API
      total_products = external_data["data"].count
      products_with_names = external_data["data"].count { |product| product["name"] }

      puts "📦 Total products in API: #{total_products}"
      puts "📜 Products with names: #{products_with_names}"
      external_titles = external_data["data"].map { |product| product["name"]}.compact
      puts "external titles are given bellow:#{external_titles}"
      puts "✅ Found #{external_titles.count} product titles in the external feed."


      # Vendors whose products should be checked & removed if missing
      target_vendors = ["ASICS","CROCS", "PUMA", "AIR JORDAN", "ON", "NIKE", "ADIDAS", "NEW BALANCE", "VANS"]

      # Fetch all Shopify products with pagination
      all_shopify_products = fetch_all_shopify_products
      puts "✅ Fetched #{all_shopify_products.count} products from Shopify."
      # binding.pry
      # Identify Shopify products not in the external feed
      products_to_remove = []

   all_shopify_products.each do |product|
     # Check if product belongs to the target vendors
     next unless target_vendors.include?(product["vendor"])

     # ✅ Normalize product title (downcase + strip spaces)
     product_title = product["title"]
      
     # ✅ If title is NOT in the external feed, mark for deletion
     unless external_titles.include?(product_title)
       products_to_remove << { id: product["id"], title: product["title"], vendor: product["vendor"] }
     end

   end


      puts "🚨 Found #{products_to_remove.count} extra products from target vendors to remove."

      # Remove products from Shopify
      products_to_remove.each do |product|
        productID = product[:id]
        delete_shopify_product(productID)
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



  def extract_next_page_info(response)
    link_header = response.headers["link"]
    return nil unless link_header

    # Extract "next" page_info from Shopify's pagination header
    match = link_header.match(/page_info=([^&>]+).*rel="next"/)
    match[1] if match
  end



  def fetch_all_shopify_products
    client = ShopifyAPI::Clients::Graphql::Admin.new(session: @session)
    products = []
    cursor = nil
    has_next_page = true

    while has_next_page
      query = <<~GRAPHQL
        query($cursor: String) {
          products(first: 100, after: $cursor) {
            edges {
              node {
                id
                title
                vendor
                variants(first: 100) {
                  edges {
                    node {
                      sku
                    }
                  }
                }
              }
              cursor
            }
            pageInfo {
              hasNextPage
            }
          }
        }
      GRAPHQL

      response = client.query(query: query, variables: { cursor: cursor })

      if response.code == 200
        body = response.body  # No need to parse JSON again

        if body["errors"]
          return render json: { error: body["errors"] }, status: :unprocessable_entity
        end

        product_edges = body.dig("data", "products", "edges") || []

        product_edges.each do |edge|
          product = edge["node"]
          product["variants"] = product["variants"]["edges"].map { |v| v["node"]["sku"] }.compact
          products << product
        end

        has_next_page = body.dig("data", "products", "pageInfo", "hasNextPage")
        cursor = product_edges.last&.dig("cursor")

        break unless has_next_page
      else
        return render json: { error: "API Request Failed", details: response.body }, status: :bad_request
      end
    end

    puts "✅ Fetched #{products.count} products from Shopify using GraphQL."
    return products
    # ✅ Return JSON response
    # render json: { total_products: products.count, products: products }, status: :ok
  end

  def delete_shopify_product(product_id)
    # gid = "gid://shopify/Product/8408492015846"
    prod_id = product_id.split('/').last

# puts product_id  # ➝ "8408492015846"

     
# binding.pry
    if @session.nil?
      puts "❌ Error: No active session found. Ensure authentication is properly configured."
      return
    end

    client = ShopifyAPI::Clients::Rest::Admin.new(session: @session)

    begin
      response = client.delete(path: "products/#{prod_id}.json")

      # Check if deletion was successful
      if response.code == 200 || response.code == 204
        puts "✅ Successfully deleted product ID: #{prod_id}"
      else
        puts "❌ Failed to delete product ID: #{prod_id}, Response Code: #{response.code}, Error: #{response.body.inspect}"
      end

    rescue ShopifyAPI::Errors::HttpResponseError => e
      puts "⚠️ Shopify API Error: #{e.message}"
    rescue StandardError => e
      puts "⚠️ Unexpected Error: #{e.message}"
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
