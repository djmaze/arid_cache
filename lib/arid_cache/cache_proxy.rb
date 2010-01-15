module AridCache
  class CacheProxy
    attr_accessor :object, :key, :opts, :blueprint, :cached, :cache_key, :block, :records, :combined_options, :klass
    
    # AridCache::CacheProxy::Result
    #
    # This struct is stored in the cache and stores information we need
    # to re-query for results.
    Result = Struct.new(:ids, :klass, :count) do
      
      def has_count?
        !count.nil?
      end
        
      def has_ids?
        !ids.nil?
      end
            
      def klass=(value)
        self['klass'] = value.is_a?(Class) ? value.name : value.class.name
      end
      
      def klass
        self['klass'].constantize unless self['klass'].nil?
      end
    end

    #
    # Managing your caches
    # 
    
    def self.clear_caches
      Rails.cache.delete_matched(%r[arid-cache-.*])
    end 
    
    def self.clear_class_caches(object)
      key = (object.is_a?(Class) ? object : object.class).name.downcase + '-'
      Rails.cache.delete_matched(%r[arid-cache-#{key}.*])
    end 
        
    def self.clear_instance_caches(object)
      key = (object.is_a?(Class) ? object : object.class).name.pluralize.downcase
      Rails.cache.delete_matched(%r[arid-cache-#{key}.*])
    end

    #
    # Fetching results
    #
    
    def self.fetch_count(object, key, opts, &block)
      CacheProxy.new(object, key, opts, &block).fetch_count
    end
          
    def self.fetch(object, key, opts, &block)
      CacheProxy.new(object, key, opts, &block).fetch
    end

    def initialize(object, key, opts, &block)
      self.object = object
      self.key = key
      self.opts = opts.symbolize_keys || {}
      self.blueprint = AridCache.store.find(object, key)
      self.block = block
      self.records = nil
      
      # The options from the blueprint merged with the options for this call
      self.combined_options = self.blueprint.nil? ? self.opts : self.blueprint.opts.merge(self.opts)
      
      self.cache_key = object.arid_cache_key(key, opts_for_cache_key)
      self.cached = Rails.cache.read(cache_key, opts_for_cache)
    end
            
    def fetch_count
      if refresh_cache?
        execute_count
      elsif cached.is_a?(AridCache::CacheProxy::Result)
        cached.has_count? ? cached.count : execute_count
      elsif cached.is_a?(Fixnum)
        cached
      elsif cached.respond_to?(:count)
        cached.count
      else
        cached # what else can we do? return it
      end
    end
          
    def fetch
      if refresh_cache?
        execute_find
      elsif cached.is_a?(AridCache::CacheProxy::Result)
        if cached.has_ids?
          self.klass = cached.klass || object_base_class
          fetch_from_cache
        else
          execute_find
        end
      else
        cached # some base type, return it
      end
    end
      
    private

      def fetch_from_cache
        if paginate?
          fetch_and_paginate
        elsif limit_or_offset?
          fetch_and_limit
        else
          klass.find(cached.ids, opts_for_find)
        end        
      end
      
      def fetch_and_paginate
        if combined_options.include?(:order) # order and paginate in the database
          klass.paginate(cached.ids, opts_for_find.merge(opts_for_paginate))
        else # paginate in memory
          paged_ids = cached.ids.paginate(opts_for_paginate)
          paged_ids.replace(klass.find(paged_ids, opts_for_find(paged_ids)))
        end        
      end
      
      def fetch_and_limit
        if combined_options.include?(:order)
          klass.find(cached.ids, opts_for_find)
        else
          offset, limit = combined_options.delete(:offset) || 0, combined_options.delete(:limit) || cached.count
          ids = cached.ids[offset, limit]
          klass.find(ids, opts_for_find(ids))
        end          
      end
      
      def paginate?
        combined_options.include?(:page)
      end
      
      def limit_or_offset?
        combined_options.include?(:limit) || combined_options.include?(:offset)
      end
      
      def refresh_cache?
        cached.nil? || opts[:force]
      end
      
      def get_records
        block = block || (blueprint && blueprint.proc)
        self.records = block.nil? ? object.instance_eval(key) : object.instance_eval(&block)
      end
      
      def execute_find
        get_records        
        cached = AridCache::CacheProxy::Result.new
        
        if !records.is_a?(Enumerable) || (!records.empty? && !records.first.is_a?(::ActiveRecord::Base))
          cached = records # some base type, cache it as itself
        else
          cached.ids = records.collect(&:id)
          cached.count = records.size
          if records.respond_to?(:proxy_reflection) # association proxy
            cached.klass = records.proxy_reflection.klass
          elsif !records.empty?
            cached.klass = records.first.class
          else
            cached.klass = object_base_class
          end
        end
        Rails.cache.write(cache_key, cached, opts_for_cache)
        
        self.cached = cached
        return_records(records)
      end

      # Convert records to an array before calling paginate.  If we don't do this
      # and the result is a named scope, paginate will trigger an additional query
      # to load the page rather than just using the records we have already fetched.
      #
      # If we are not paginating and the options include :limit (and optionally :offset)
      # apply the limit and offset to the records before returning them.
      #
      # Otherwise we have an issue where all the records are returned the first time
      # the collection is loaded, but on subsequent calls the options_for_find are
      # included and you get different results.  Note that with options like :order
      # this cannot be helped.  We don't want to modify the query that generates the
      # collection because the idea is to allow getting different perspectives of the
      # cached collection without relying on modifying the collection as a whole.
      #
      # If you do want a specialized, modified, or subset of the collection it's best
      # to define it in a block and have a new cache for it:
      #
      # model.my_special_collection { the_collection(:order => 'new order', :limit => 10) }      
      def return_records(records)
        if opts.include?(:page)
          records = records.respond_to?(:to_a) ? records.to_a : records
          records.respond_to?(:paginate) ? records.paginate(opts_for_paginate) : records
        elsif opts.include?(:limit)
          records = records.respond_to?(:to_a) ? records.to_a : records
          offset = opts[:offset] || 0 
          records[offset, opts[:limit]]
        else
          records
        end      
      end
      
      def execute_count
        get_records
        cached = AridCache::CacheProxy::Result.new

        # Just get the count if we can.
        #
        # Because of how AssociationProxy works, if we even look at it, it'll
        # trigger the query.  So don't look.
        #
        # Association proxy or named scope.  Check for an association first, because
        # it doesn't trigger the select if it's actually named scope.  Calling respond_to?
        # on an association proxy will hower trigger a select because it loads up the target
        # and passes the respond_to? on to it.
        if records.respond_to?(:proxy_reflection) || records.respond_to?(:proxy_options)
          cached.count = records.count # just get the count
          cached.klass = object_base_class
        elsif records.is_a?(Enumerable) && (records.empty? || records.first.is_a?(::ActiveRecord::Base))
          cached.ids = records.collect(&:id) # get everything now that we have it
          cached.count = records.size
          cached.klass = records.empty? ? object_base_class : records.first.class
        else
          cached = records # some base type, cache it as itself
        end
        
        Rails.cache.write(cache_key, cached, opts_for_cache)
        self.cached = cached
        cached.respond_to?(:count) ? cached.count : cached
      end
      
      OPTIONS_FOR_PAGINATE = [:page, :per_page, :total_entries]
      
      # Filter options for paginate, if *klass* is set, we get the :per_page value from it.
      def opts_for_paginate
        paginate_opts = combined_options.reject { |k,v| !OPTIONS_FOR_PAGINATE.include?(k) }
        paginate_opts[:per_page] = klass.per_page if klass && !paginate_opts.include?(:per_page)
        paginate_opts
      end
    
      OPTIONS_FOR_FIND = [ :conditions, :include, :joins, :limit, :offset, :order, :select, :readonly, :group, :having, :from, :lock ]

      # Preserve the original order of the results if no :order option is specified.
      # 
      # @arg ids array of ids to order by unless an :order option is specified.  If not
      #      specified, cached.ids is used.
      def opts_for_find(ids=nil)
        ids ||= cached.ids
        find_opts = combined_options.reject { |k,v| !OPTIONS_FOR_FIND.include?(k) }
        find_opts[:order] = preserve_order(ids) unless find_opts.include?(:order)
        find_opts
      end
      
      OPTIONS_FOR_CACHE = [ :expires_in ]
      
      def opts_for_cache
        combined_options.reject { |k,v| !OPTIONS_FOR_CACHE.include?(k) }
      end

      OPTIONS_FOR_CACHE_KEY = [ :auto_expire ]
      
      def opts_for_cache_key
        combined_options.reject { |k,v| !OPTIONS_FOR_CACHE_KEY.include?(k) }
      end
            
      def object_base_class #:nodoc:
        object.is_a?(Class) ? object : object.class
      end

      # Generate an ORDER BY clause that preserves the ordering of the ids in *ids*.
      #
      # The method we use depends on the database adapter because only MySQL 
      # supports the ORDER BY FIELD() function.  For other databases we use
      # a CASE statement.
      # 
      # TODO: is it quicker to sort in memory?
      def preserve_order(ids)
        if ::ActiveRecord::Base.is_mysql_adapter?
          "FIELD(id,#{ids.join(',')})" 
        else
          order = ''
          ids.each_index { |i| order << "WHEN id=#{ids[i]} THEN #{i+1} " }
          "CASE " + order + " END"
        end
      end 
  end
end