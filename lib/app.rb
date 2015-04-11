#
# ¯\_(ツ)_/¯
#
require 'rubygems'
require 'bundler/setup'
require 'sinatra/base'
require 'sinatra/contrib/all'
require 'sinatra/json'
require 'json'
require 'mysql2'
require 'bitly'
require 'chartkick'
require 'active_support/time'

require_relative 's9y'
# require 'moneta'
# require 'active_record'

class SocialCasterApp < Sinatra::Base

  APPNAME = "S9Y SocialCaster"

  use Rack::MethodOverride

  register Sinatra::Contrib
  register Sinatra::ConfigFile

  helpers Sinatra::SocialCasterApp::Helpers

  set :root, File.dirname(File.dirname(__FILE__))
  set :sessions, true
  set :logging, true

  config_file 'config/config.yml'
  set :protection, :except => :frame_options

  configure :development do
    set :session_secret, "secret"
    set :logging, Logger::DEBUG
  end

  get "/" do
    redirect to('/twitter/posts/report')
  end

  post "/api/tweet" do
    content_type :json
    request.body.rewind  # in case someone already read it
    params = JSON.parse request.body.read

    logger.debug("POST /api/tweet - params: #{params.inspect} ")

    response = Hash.new
    if validate_token(params['token'])
      logger.info("POST /api/tweet - Got correct token.")

      tweet = generate_tweet

      if tweet[:status] === "error"
        raise tweet.to_json
      end

      tweet[:timestamp] = DateTime.now.change(:offset => settings.zone_offset).to_s
      tweet_text = tweet[:body]
      response[:tweet_body] = tweet_text

      if settings.send_tweets
        if tweet_id = send_tweet(tweet_text)
          response[:tweet_sent] = true
          tweet[:status] = "sent"
          tweet[:id] = tweet_id
        else
          response[:tweet_sent] = false
          tweet[:status] = "error"
          tweet[:id] = tweet_id
        end
      else
        response[:tweet_sent] = false
        tweet[:status] = "not sent"
        tweet_text
      end

      response[:status] = 200
      response[:status_message] = "Success"

      do_reporting("twitter", tweet)
      json tweet
    else
      response[:status] = 400
      response[:status_message] = "Bad Request"
      json response
    end
  end

  get "/update_reports" do
    logger.debug("GET /update_reports")
    update_bitly_reports.to_s
  end

  get "/:type/posts/report" do
    reporting = S9Y::SocialCaster::Reporting.new(settings.reporting, logger)
    logger.debug("got instance of reporting: #{reporting.inspect}")
    @data = reporting.get_data(params[:type])
    logger.debug("got data: #{@data.inspect}")
    erb :posts_report
  end

  get "/:type/categories/report" do
    reporting = S9Y::SocialCaster::Reporting.new(settings.reporting, logger)
    logger.debug("got instance of reporting: #{reporting.inspect}")
    @categories = reporting.get_category_stats(params[:type])
    logger.debug("got data: #{@categories.inspect}")
    erb :categories_report
  end

  get "/:type/posts/clicks" do
    reporting = S9Y::SocialCaster::Reporting.new(settings.reporting, logger)
    logger.debug("got instance of reporting: #{reporting.inspect}")
    last_posts = reporting.get_last_posts(params[:type], 10)
    logger.debug("got last posts: #{last_posts.inspect}")

    bitlyclient = Bitly.client
    @stats = reporting.get_clicks_by_link(bitlyclient, last_posts.values)
    erb :posts_clicks
  end

  get "/:type/categories/clicks" do
    erb :categories_clicks
  end

  not_found do
    'This is nowhere to be found.'
  end

  error do
    'Sorry there was a nasty error - ' + env['sinatra.error'].name
  end

  private

end
