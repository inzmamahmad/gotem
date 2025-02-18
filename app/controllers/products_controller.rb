
require 'uri'
require 'net/http'
require 'tempfile'
# require 'roo'

class ProductsController < ApplicationController
  before_action :shopify_session, only: %i[index ]
  def index
  	# debugger
    @products = ShopifyAPI::Product.all(session: @session)
    @count = ShopifyAPI::Product.count(session: @session, vendor: 'Rough Country')
    puts "count is:#{@count.body['count']}"
    puts "count is:#{@count.body['count']}"
    if @products.present?
      render json: @products
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

