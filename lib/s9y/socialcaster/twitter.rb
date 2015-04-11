module SocialCaster

  module Twitter
    require 'twitter'

    def generate_tweet
      logger.info("generate_tweet - Start")

      max_chars = 140
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

      if settings.add_via and (tweet_text.length + " via @#{settings.twitter[:username]}".length) < max_chars
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

      client = ::Twitter::REST::Client.new do |config|
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
  end
end
