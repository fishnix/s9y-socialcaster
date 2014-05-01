#
# ¯\_(ツ)_/¯
#
require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'sinatra/config_file'
require 'sinatra/json'
require 'json'
require 'mysql2'
require 'bitly'
require 'twitter'
require 'chartkick'
# require 'moneta'
# require 'active_record'

use Rack::MethodOverride

@@appname = "S9Y SocialCaster"

config_file 'config.yml'
set :protection, :except => :frame_options

configure :development do
  set :logging, Logger::DEBUG
end

@@mysqlclient = Mysql2::Client.new(  :host => settings.database[:mysql_host], 
                                     :username => settings.database[:mysql_user],
                                     :password => settings.database[:mysql_pass],
                                     :database => settings.database[:mysql_db],
                                     :reconnect => true
                                   )

Bitly.configure do |config|
  config.api_version = 3
  config.login = settings.shortener[:username]
  config.api_key = settings.shortener[:token]
end

get "/" do
  "#{appname}! <br />"
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

    tweet[:timestamp] = DateTime.now.to_s
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

def validate_token(token)
  logger.info("validate_token - start")
  token === settings.secret_token
end

def mysql_query(statement=nil, options={})
  logger.info("query - start")
  logger.debug("query - statement: #{statement}, options: #{options.inspect}")
  begin
    logger.debug("query - checking database connection is still alive: #{@@mysqlclient.ping}")
    result = @@mysqlclient.query(statement, options)
    logger.debug("query - result: #{result.inspect}")
    result
  rescue
    logger.error("query - Ouch... something went wrong.")
    nil
  end
end

def get_category_id(categories=nil)
  logger.info("get_category_id - Start")
  category_ids = []
  [*categories].each do |c|
    logger.info("get_category_id - Getting category id for #{c}")
    result = mysql_query("select categoryid from #{settings.database[:table_prefix]}category where category_name=\"#{c}\"")
    category_id = result.first['categoryid'].to_s
    logger.info("get_category_id - Got category id #{category_id}")
    category_ids << category_id
  end
  logger.info("get_category_id - List of category ids: #{category_ids.inspect}")
  category_ids
end

def get_category_name(category_ids=[])
  logger.info("get_category_name - Start")
  
  category_names = []
  if category_ids.empty?
    logger.info("get_category_name - Returning empty category list.")
    return []
  end
  
  [*category_ids].each do |c|
    logger.info("get_category_name - Getting category name for #{c}")
    result = mysql_query("select category_name from #{settings.database[:table_prefix]}category where categoryid=\"#{c}\"")
    category_name = result ? result.first['category_name'].to_s : nil
    logger.info("get_category_name - Got category name #{category_name}")
    category_names << category_name
  end
  logger.info("get_category_name - List of category names: #{category_names.inspect}")
  category_names
end

def get_max_entry_id
  logger.info("get_max_entry_id - Start")
  result = mysql_query("select max(id) from #{settings.database[:table_prefix]}entries")
  max_entry_id = result.first['max(id)'].to_s
  logger.debug("get_max_entry_id - Got result: #{result.inspect}")
  logger.info("get_max_entry_id - returning #{max_entry_id}")
  max_entry_id.to_i
end

def get_entries_by_category(categories=nil)
  logger.info("get_entries_by_category - Start")
  entry_ids = []
  [*categories].each do |c|
    logger.info("get_entries_by_category - Getting entry ids for category: #{c}")
    result = mysql_query("select entryid from #{settings.database[:table_prefix]}entrycat where categoryid=\"#{c}\"", {:as => :array})
    result.each do |r|
      entry_ids << r.first
    end
  end
  logger.info("get_entries_by_category - Got #{entry_ids.count} entries")
  logger.debug("get_entries_by_category - List of entry ids: #{entry_ids.inspect}")
  entry_ids
end

def get_categories_by_entry(entry_id=nil)
  logger.info("get_categories_by_entry - Start")
  category_ids = []
  logger.info("get_categories_by_entry - Getting category ids for entry: #{entry_id}")
  result = mysql_query("select categoryid from #{settings.database[:table_prefix]}entrycat where entryid=\"#{entry_id}\"", {:as => :array})
  result.each do |r|
    category_ids << r.first
  end
  logger.info("get_categories_by_entry - Got #{category_ids.count} categories")
  logger.debug("get_categories_by_entry - List of category ids: #{category_ids.inspect}")
  category_ids
end

def get_random_id(max=1, excl=nil, incl=nil)
  logger.info("get_random_id - Start")
  logger.debug("get_random_id - options: max: #{max.inspect}, exclude: #{excl.inspect}, include: #{incl.inspect}")
  
  tries = 0
  number = Random.new().rand(max)
  
  unless incl.empty?
    logger.debug("get_random_id - Generating random number from include list: #{incl.inspect}")
    number = incl.sample
    logger.info("get_random_id - Got random number from include list: #{number}")
  end
  
  unless excl.empty?
    logger.debug("get_random_id - Received an exclude list #{excl.inspect}")
    while excl.include?(number)
      
      if tries >= settings.tries_limit
        raise "Could't select an entry in the allowed number of tries!" 
      end
      
      logger.info("get_random_id - checking #{number} against exclude list. try number: #{tries}")
      unless incl.empty?
        number = incl.sample
      else
        number = Random.new().rand(max)
      end
      tries += 1
    end
  end
    
  logger.info("get_random_id - returning #{number}")
  number
end

def get_permalink_from_id(entry_id=0)
  logger.info("get_permalink_from_id - Start")
  result = mysql_query(" select permalink from #{settings.database[:table_prefix]}permalinks where entry_id=#{entry_id} and type='entry'")
  permalink = settings.base_url.chomp('/') + '/' + result.first["permalink"]
  logger.info("get_permalink_from_id - returning #{permalink.inspect}")
  permalink
end

def get_random_entry
  logger.info("get_random_entry - Start")
  
  max_entry_id = get_max_entry_id
  
  logger.info("get_random_entry - Getting details for exlcuded categories.")
  excluded_categories = get_category_id(settings.excluded_categories)
  excluded_entries = get_entries_by_category(excluded_categories)
  
  logger.info("get_random_entry - Getting details for included categories.")
  included_categories = get_category_id(settings.included_categories)
  included_entries = get_entries_by_category(included_categories)
  
  entry_id = get_random_id(max_entry_id, excluded_entries, included_entries )
  result = mysql_query("select * from #{settings.database[:table_prefix]}entries where id=#{entry_id}")
  entry = result.first
  
  logger.debug("get_random_entry - Got entry #{entry.inspect}")
  logger.info("get_random_entry - Returning entry id: #{entry['id']} title: #{entry['title']}")
  
  categories = get_category_name(get_categories_by_entry(entry["id"]))
  
  permalink = get_permalink_from_id(entry["id"])
  short_url = shorten_url(permalink)
  
  { 
    "id"          => entry["id"],
    "title"       => entry["title"],
    "url"         => permalink,
    "link"        => short_url,
    "categories"  => categories
  }
end

def shorten_url(url=nil)
  logger.info("shorten_url - Start")
  
  logger.info("shorten_url - Attempting to shorten url: #{url}")
  
  begin
    bitlyclient = Bitly.client
    surl = bitlyclient.shorten(url)
    logger.debug("shorten_url - Got response: #{surl.inspect}")
    logger.info("shorten_url - Got back: #{surl.short_url}")
    surl.short_url
  rescue
    logger.error("shorten_url - Unable to shorten URL!")
    nil
  end
end

def generate_tweet
  logger.info("generate_tweet - Start")
  
  max_chars = 140
  
  max = get_max_entry_id.to_i
  rand_entry = get_random_entry

  teaser_text = settings.teasers.sample
  
  tweet_text = "#{teaser_text}"
  tweet_text << " " unless tweet_text.empty?
  tweet_text << "\"#{rand_entry["title"]}\" "
  
  if rand_entry["link"].nil?
    if (tweet_text.length + rand_entry["url"].length) < max_chars
      tweet_text << "#{rand_entry["url"]}"
    else
      logger.error("generate_tweet - Didnt get short URL and long url is too long for tweet!")
      err = { 
              :status => "error",
              :message => "Couldnt get short url and long url is too long."
            }
      return err
    end
  else
    tweet_text << "#{rand_entry["link"]}"
  end
  
  rand_entry["categories"].each do |c|
    cat = c.gsub(/[^0-9a-z_]/i, '')
    if (tweet_text.length + " ##{cat.downcase}".length) < max_chars
      tweet_text << " ##{cat.downcase}"
    end
  end
  
  if (tweet_text.length + " via @#{settings.twitter[:username]}".length) < max_chars
    tweet_text << " via @#{settings.twitter[:username]}"
  end
  
  logger.info("generate_tweet - Generated tweet text: \'#{tweet_text}\' with length: #{tweet_text.length}")
  
  {
    :status => "success",
    :body => tweet_text,
    :categories => rand_entry["categories"],
    :link => rand_entry["link"]
  }
end

def send_tweet(text=nil)
  logger.info("send_tweet - Start")
  
  client = Twitter::REST::Client.new do |config|
    config.consumer_key        = settings.twitter[:consumer_key]
    config.consumer_secret     = settings.twitter[:consumer_secret]
    config.access_token        = settings.twitter[:access_token]
    config.access_token_secret = settings.twitter[:access_token_secret]
  end
  
  begin
    logger.info("send_tweet - sending Tweet!")
    tweet = client.update(text)
    logger.debug("send_tweet - tweet: #{tweet.inspect}, client: #{client.inspect}")
    tweet.id
  rescue
    logger.error("send_tweet - unable to send tweet!")
    nil
  end
end

def do_reporting(type, content)
  reporting = S9Y::SocialCaster::Reporting.new(settings.reporting, logger)
  logger.debug("got instance of reporting: #{reporting.inspect}")
  reporting.add_post(type, content[:timestamp])
  reporting.add_post_detail(type, content)
  unless content[:categories].nil?
    content[:categories].each do |c|
      reporting.incr_category(type, c)
    end
  end
  reporting.add_post_links(type, content)
end

module S9Y
  module SocialCaster
    class Reporting
      require 'redis'
      require 'date'
      require 'json'
    
      def initialize(args, logger)
        redis_host  = args[:redis_host] || '127.0.0.1'
        redis_port  = args[:redis_port] || '6379'
        @logger     = logger
        @redis = Redis.new(:host => redis_host, :port => redis_port)
      end
    
      def ping
        begin
          @redis.connected?
        rescue
          @redis.connect
          raise "Cannot connect to redis!" unless @redis.connected?
        end
      end
    
      def add_post(type, date)
        @logger.info("add_post - start")

        begin
          @logger.info("add_post - Adding post #{date} to redis list #{type}_post")            
          @redis.rpush("#{type}_post", date)
        rescue
          @logger.error("add_post - Couldn't write to redis!")
        end
      end

      def add_post_detail(type, content)
        @logger.info("add_post_detail - start")

        begin
          @logger.info("add_post_detail - Adding to redis report: #{content.to_json}")
          @logger.debug("add_post_detail - content: #{content.to_json}")        
          @redis.hset("#{type}_detail", content[:timestamp], content.to_json)
        rescue
          @logger.error("add_post_detail - Couldn't write to redis!")
        end
      end
      
      def incr_category(type, category)
        @logger.info("incr_category - start")
        begin
          @logger.info("incr_category - Incrementing category: #{category} in: #{type}_category")
          @redis.hincrby("#{type}_category", category, 1)
        rescue
          @logger.error("incr_category - Couldn't increment category! #{category}")
        end
      end
      
      def add_post_links(type, content)
        @logger.info("add_post_links - start")
        @logger.debug("add_post_links - #{content.inspect}")
        begin
          link = content[:link] || content[:url]
          @logger.info("add_post_links - Adding post/link info: #{content[:timstamp]} => #{link}")
          @redis.hset("#{type}_post_link", content[:timestamp], link)
        rescue
          @logger.error("add_post_links - Couldn't add post/link record!")
        end
      end
      
      def get_data(type)
        @logger.info("get_data - start")
        data = {}
        
        begin
          @logger.info("get_data - Getting reporting data from redis")            
          @redis.hgetall("#{type}_detail")
          @redis.hkeys("#{type}_detail").each do |k|
            d = JSON.parse(@redis.hget("#{type}_detail", k))
            data[k] = d
            @logger.info("get_data - #{k.inspect} #{d.inspect}")
          end
        rescue
          @logger.error("get_data - Couldn't get reporting data from redis!")
        end
        data
      end
      
      def get_category_stats(type)
        @logger.info("get_category_stats - start")
        data = {}
        
        begin
          @logger.info("get_category_stats - Getting reporting data from redis")            
          @redis.hkeys("#{type}_category").each do |k|
            data[k] = @redis.hget("#{type}_category", k).to_i
            @logger.info("get_category_stats - #{k.inspect} #{data[k].inspect}")
          end
        rescue
          @logger.error("get_category_stats - Couldn't get category stats data from redis!")
        end
        data
      end

      def get_last_posts(type, num)
        @logger.info("get_last_posts - start")
        data = {}
        begin
          @logger.info("get_last_posts - Getting last #{num} posts from redis")            
          @redis.sort("#{type}_post", :order => "alpha desc", :limit => [0, num]).each do |k|
            data[k] = @redis.hget("#{type}_post_link", k)
          end
          @logger.info("get_last_posts - #{data.inspect}")
        rescue
          @logger.error("get_last_posts - Couldn't get last posts from redis!")
        end
        data
      end

      def get_clicks_by_link(bitlyclient, link)
        @logger.info("get_clicks_by_link - Start")
        @logger.info("get_clicks_by_link - Getting stats for URL #{link}")
        stats = {}
        begin
          bitlyclient.clicks(link).each do |s|
            @logger.debug("get_clicks_by_link - Got response: #{s.inspect}")
            # @logger.info("get_clicks_by_link - Got back: #{stats.link_clicks} in #{stats.unit}")
            stats[s.short_url] = s.global_clicks unless s.nil?
          end
        rescue
          @logger.error("get_clicks_by_link - Unable to get stats for URL #{link}!")
          nil
        end
        stats
      end
    end
  end
end