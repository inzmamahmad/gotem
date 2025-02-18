
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
  	# puts response_body
  	# Get the first product and render it
  	first_product = response_body['data'].first['name']  # assuming the products are in 'data' field
  	puts first_product
    if first_product.present?
      render json: first_product
    end

  	# # debugger
    # @products = ShopifyAPI::Product.all(session: @session)
    # @count = ShopifyAPI::Product.count(session: @session)
    # puts "count is:#{@count.body['count']}"
    # puts "count is:#{@count.body['count']}"
    # if @products.present?
    #   render json: @products
    # end

  end

  private

    def shopify_session
      @session = ShopifyAPI::Auth::Session.new(
        shop: ENV['SHOPIFY_SHOP'],
        access_token: ENV['SHOPIFY_ACCESS_TOKEN'],
      )
    end
end

