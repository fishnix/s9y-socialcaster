#
# ¯\_(ツ)_/¯
#
require 'sinatra'
require 'sinatra/config_file'
require 'sinatra/json'
require 'json'
require 'mysql2'
require 'bitly'
require 'twitter'
#require 'active_record'

use Rack::MethodOverride

config_file 'config.yml'
set :protection, :except => :frame_options

@@mysqlclient = Mysql2::Client.new(  :host => settings.database[:mysql_host], 
                                     :username => settings.database[:mysql_user],
                                     :password => settings.database[:mysql_pass],
                                     :database => settings.database[:mysql_db],
                                     :reconnect => true
                                   )

get "/" do
  "S9Y SocialCaster! <br />"
end

get "/rand" do
  # max = get_max_entry_id.to_i
  rand_entry = get_random_entry
  # category_id = get_category_id(["Giveaways","Deals + Sales"])
  rand_entry.to_json
end

post "/api/tweet" do
  content_type :json
  request.body.rewind  # in case someone already read it
  params = JSON.parse request.body.read
  
  logger.debug("POST /api/tweet - params: #{params.inspect} ")
  
  response = Hash.new
  if params['token'] === settings.secret_token
    logger.info ("POST /api/tweet - Got correct token.")
    
    tweet_text = generate_tweet
    response[:tweet_body] = tweet_text
    
    if settings.send_tweets
      response[:tweet_sent] = true
      send_tweet(tweet_text)
    else
      response[:tweet_sent] = false
      tweet_text
    end
    
    response[:status] = 200
    response[:message] = "Success"
  else
    response[:status] = 400
    response[:message] = "Bad Request"
  end
   
  json response
end

not_found do
  'This is nowhere to be found.'
end

error do
  'Sorry there was a nasty error - ' + env['sinatra.error'].name
end

private

def mysql_query(statement=nil, options={})
  logger.info("query - start")
  logger.debug("query - statement: #{statement}, options: #{options.inspect}")
  result = @@mysqlclient.query(statement, options)
  logger.debug("query - result: #{result.inspect}")
  result
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
    return category_names
  end
  
  [*category_ids].each do |c|
    logger.info("get_category_name - Getting category name for #{c}")
    result = mysql_query("select category_name from #{settings.database[:table_prefix]}category where categoryid=\"#{c}\"")
    category_name = result.first['category_name'].to_s
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
    "link"        => short_url,
    "categories"  => categories
  }
end

def shorten_url(url=nil)
  logger.info("shorten_url - Start")
  
  logger.info("shorten_url - Attempting to shorten url: #{url}")
  Bitly.use_api_version_3
  bitlyclient = Bitly.new(settings.shortener[:username], settings.shortener[:token])
  surl = bitlyclient.shorten(url)
  logger.debug("shorten_url - Got response: #{surl.inspect}")
  logger.info("shorten_url - Got back: #{surl.short_url}")
  surl.short_url
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
  tweet_text << "#{rand_entry["link"]}"
  
  if (tweet_text.length + settings.twitter[:username].length + 1) < max_chars
    tweet_text << " @#{settings.twitter[:username]}"
  end
  
  logger.info("generate_tweet - Generated tweet text: \'#{tweet_text}\' with length: #{tweet_text.length}")
  
  tweet_text
end

def send_tweet(text=nil)
  logger.info("send_tweet - Start")
  
  client = Twitter::REST::Client.new do |config|
    config.consumer_key        = settings.twitter[:consumer_key]
    config.consumer_secret     = settings.twitter[:consumer_secret]
    config.access_token        = settings.twitter[:access_token]
    config.access_token_secret = settings.twitter[:access_token_secret]
  end
  
  logger.info("send_tweet - sending Tweet!")
  client.update(text)
end