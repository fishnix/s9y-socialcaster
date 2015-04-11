module SocialCaster
  class Shortener

    def initialize(options = {})
      Bitly.use_api_version_3
      @client         = Bitly.new(options[:login], options[:api_key])
      @client.timeout = options[:timeout] || 30
      @logger         = options[:@logger] || Logger.new(STDOUT)
    end

    def shorten_url(url=nil)
      @logger.info("shorten_url - Start")
      @logger.info("shorten_url - Attempting to shorten url: #{url} with #{@client.inspect}")

      begin
        surl = @client.shorten(url)
        @logger.debug("shorten_url - Got response: #{surl.inspect}")
        @logger.info("shorten_url - Got back: #{surl.short_url}")
        surl.short_url
      rescue => e
        @logger.error("shorten_url - Unable to shorten URL! #{e}")
        nil
      end
    end
  end
end
