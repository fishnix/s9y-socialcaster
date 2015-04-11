require_relative 'database'
require_relative 'shortener'
require_relative 'twitter'

module Sinatra
  module SocialCasterApp
    module Helpers

      private
      include SocialCaster::Twitter

      def validate_token(token)
        logger.info("validate_token - start")
        token === settings.secret_token
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

      def get_random_entry
        logger.info("get_random_entry - Start")

        mysqlclient = SocialCaster::Database.new(:host     => settings.database[:mysql_host],
                                                 :username => settings.database[:mysql_user],
                                                 :password => settings.database[:mysql_pass],
                                                 :database => settings.database[:mysql_db])

        max_entry_id = mysqlclient.get_max_entry_id

        logger.info("get_random_entry - Getting details for exlcuded categories.")
        excluded_categories = mysqlclient.get_category_id(settings.excluded_categories)
        excluded_entries = mysqlclient.get_entries_by_category(excluded_categories)

        logger.info("get_random_entry - Getting details for included categories.")
        included_categories = mysqlclient.get_category_id(settings.included_categories)
        included_entries = mysqlclient.get_entries_by_category(included_categories)

        entry_id = get_random_id(max_entry_id, excluded_entries, included_entries )
        entry = mysqlclient.get_entry_by_id(entry_id)

        logger.debug("get_random_entry - Got entry #{entry.inspect}")
        logger.info("get_random_entry - Returning entry id: #{entry['id']} title: #{entry['title']}")

        categories = mysqlclient.get_category_name(mysqlclient.get_categories_by_entry(entry["id"]))
        permalink = settings.base_url.chomp('/') + '/' + mysqlclient.get_permalink_from_id(entry["id"])

        shortener = SocialCaster::Shortener.new(login: settings.shortener[:username],
                                                api_key: settings.shortener[:token],
                                                timeout: 60)
        short_url = shortener.shorten_url(permalink)

        {
            "id"          => entry["id"],
            "title"       => entry["title"],
            "url"         => permalink,
            "link"        => short_url,
            "categories"  => categories
        }
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
        link = content[:link] || content[:url]
        reporting.add_bitly_link(link)
        reporting.add_post_links(type, content)
      end

      def update_bitly_reports
        reporting = S9Y::SocialCaster::Reporting.new(settings.reporting, logger)
        logger.debug("update_bitly_reports - got instance of reporting: #{reporting.inspect}")
        bitlyclient = Bitly.client
        stats = reporting.get_clicks_by_link(bitlyclient, reporting.get_last_bitly_links(10))
        logger.info("update_bitly_reports - #{stats.inspect}")
        stats
      end
    end
  end
end
