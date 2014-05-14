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

      def add_bitly_link(link)
        @logger.info("add_bitly_link - start")

        begin
          @logger.info("add_bitly_link - Adding linke #{link} to redis list bitly_links")            
          @redis.rpush("bitly_links", link)
        rescue
          @logger.error("add_bitly_link - Couldn't write to redis!")
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
            @logger.info("get_last_posts - post: #{k.inspect}")
            data[k] = @redis.hget("#{type}_post_link", k)
          end
          @logger.info("get_last_posts - #{data.inspect}")
        rescue
          @logger.error("get_last_posts - Couldn't get last posts from redis!")
        end
        data
      end

      def get_last_bitly_links(num)
        @logger.info("get_last_bitly_links - start")
        links = []
        # begin
          @logger.info("get_last_bitly_links - Getting last #{num} links from redis")            
          links = @redis.sort("bitly_links", :order => "alpha desc", :limit => [0, num])
          @logger.info("get_last_bitly_links - #{links.inspect}")
        # rescue
          @logger.error("get_last_bitly_links - Couldn't get last links from redis!")
        # end
        links
      end

      def get_clicks_by_link(bitlyclient, link)
        @logger.info("get_clicks_by_link - Start")
        @logger.info("get_clicks_by_link - Getting stats for URL #{link}")
        stats = {}
        begin
          [*bitlyclient.clicks(link)].each do |s|
            @logger.debug("get_clicks_by_link - Got response: #{s.inspect}")
            stats[s.short_url] = s.global_clicks unless s.nil?
            @logger.debug("get_clicks_by_link - Adding to bitly_clicks: link: #{s.short_url} clicks: #{stats[s.short_url]}")
            @redis.hset("bitly_clicks", s.short_url, stats[s.short_url])
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