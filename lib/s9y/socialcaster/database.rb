module SocialCaster
  class Database
    require 'mysql2'

    def initialize(options = {})
      @database  = options[:database] || 's9y'
      @host      = options[:host]     || '127.0.0.1'
      @username  = options[:username] || 'root'
      @password  = options[:password] || 'ilikerandompasswords'
      @prefix    = options[:prefix]   || 'serendipity_'
      @logger    = options[:@logger]  || Logger.new(STDOUT)
    end

    def mysql_query(statement = nil, options = {})
      @logger.info("query - start")
      @logger.debug("query - statement: #{statement}, options: #{options.inspect}")
      begin
        client = Mysql2::Client.new(host:     @host,
                                    username: @username,
                                    password: @password,
                                    database: @database,
                                    :reconnect => true)
        @logger.debug("query - checking database connection is still alive: #{client.ping}")
        result = client.query(statement, options)
        @logger.debug("query - result: #{result.inspect}")
        result
      rescue => e
        @logger.error("query - Ouch... something went wrong. #{e}")
        nil
      ensure
        client.close unless client.nil?
      end
    end

    def get_entry_by_id(entry_id = nil)
      mysql_query("select * from #{@prefix}entries where id=#{entry_id}").first
    end

    def get_category_id(categories = nil)
      @logger.info("get_category_i d - Start")
      category_ids = []
      [*categories].each do |c|
        @logger.info("get_category_id - Getting category id for #{c}")
        result = mysql_query("select categoryid from #{@prefix}category where category_name=\"#{c}\"")
        category_id = result.first['categoryid'].to_s
        @logger.info("get_category_id - Got category id #{category_id}")
        category_ids << category_id
      end
      @logger.info("get_category_id - List of category ids: #{category_ids.inspect}")
      category_ids
    end

    def get_category_name(category_ids = [])
      @logger.info("get_category_name - Start")

      category_names = []
      if category_ids.empty?
        @logger.info("get_category_name - Returning empty category list.")
        return []
      end

      [*category_ids].each do |c|
        @logger.info("get_category_name - Getting category name for #{c}")
        result = mysql_query("select category_name from #{@prefix}category where categoryid=\"#{c}\"")
        category_name = result ? result.first['category_name'].to_s : nil
        @logger.info("get_category_name - Got category name #{category_name}")
        category_names << category_name
      end
      @logger.info("get_category_name - List of category names: #{category_names.inspect}")
      category_names
    end

    def get_max_entry_id
      @logger.info("get_max_entry_id - Start")
      result = mysql_query("select max(id) from #{@prefix}entries")
      max_entry_id = result.first['max(id)'].to_s
      @logger.debug("get_max_entry_id - Got result: #{result.inspect}")
      @logger.info("get_max_entry_id - returning #{max_entry_id}")
      max_entry_id.to_i
    end

    def get_entries_by_category(categories = nil)
      @logger.info("get_entries_by_category - Start")
      entry_ids = []
      [*categories].each do |c|
        @logger.info("get_entries_by_category - Getting entry ids for category: #{c}")
        query = "select t1.entryid from #{@prefix}entrycat "
        query += "t1 left join #{@prefix}entries t2 on "
        query += "t2.id = t1.entryid where t2.isdraft = 'false' and t1.categoryid=\"#{c}\""
        result = mysql_query(query, {:as => :array})
        result.each do |r|
          entry_ids << r.first
        end
      end
      @logger.info("get_entries_by_category - Got #{entry_ids.count} entries")
      @logger.debug("get_entries_by_category - List of entry ids: #{entry_ids.inspect}")
      entry_ids
    end

    def get_categories_by_entry(entry_id = nil)
      @logger.info("get_categories_by_entry - Start")
      category_ids = []
      @logger.info("get_categories_by_entry - Getting category ids for entry: #{entry_id}")
      query = "select categoryid from #{@prefix}entrycat "
      query += "where entryid=\"#{entry_id}\""
      result = mysql_query(query, {:as => :array})
      result.each do |r|
        category_ids << r.first
      end
      @logger.info("get_categories_by_entry - Got #{category_ids.count} categories")
      @logger.debug("get_categories_by_entry - List of category ids: #{category_ids.inspect}")
      category_ids
    end

    def get_permalink_from_id(entry_id = 0)
      @logger.info("get_permalink_from_id - Start")
      result = mysql_query(" select permalink from #{@prefix}permalinks where entry_id=#{entry_id} and type='entry'")
      permalink = result.first["permalink"]
      @logger.info("get_permalink_from_id - returning #{permalink.inspect}")
      permalink
    end
  end
end
