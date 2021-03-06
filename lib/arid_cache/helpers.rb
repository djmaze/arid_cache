module AridCache
  module Helpers

    # Lookup something from the cache.
    #
    # If no block is provided, create one dynamically.  If a block is
    # provided, it is only used the first time it is encountered.
    # This allows you to dynamically define your caches while still
    # returning the results of your query.
    #
    # @return a WillPaginate::Collection if the options include :page,
    #  a Fixnum count if the request is for a count or the results of
    #  the ActiveRecord query otherwise.
    def lookup(object, key, opts, &block)
      if !block.nil?
        define(object, key, opts, &block)
      elsif key =~ /(.*)_count$/
        if AridCache.store.has?(object, $1)
          method_for_cached(object, $1, :fetch_count, key)
        elsif object.respond_to?(key)
          define(object, key, opts, :fetch_count)
        elsif object.respond_to?($1)
          define(object, $1, opts, :fetch_count, key)
        else
          raise ArgumentError.new("#{object} doesn't respond to #{key} or #{$1}!  Cannot dynamically create query to get the count, please call with a block.")
        end
      elsif AridCache.store.has?(object, key)
        method_for_cached(object, key, :fetch)
      elsif object.respond_to?(key)
        define(object, key, opts, &block)
      else
        raise ArgumentError.new("#{object} doesn't respond to #{key}!  Cannot dynamically create query, please call with a block.")
      end
      object.send("cached_#{key}", opts)
    end

    # Store the options and optional block for a call to the cache.
    #
    # If no block is provided, create one dynamically.
    #
    # @return an AridCache::Store::Blueprint.
    def define(object, key, opts, fetch_method=:fetch, method_name=nil, &block)
      
      # FIXME: Pass default options to store.add
      # Pass nil in for now until we get the cache_ calls working.
      # This means that the first time you define a dynamic cache
      # (by passing in a block), the options you used are not
      # stored in the blueprint and applied to each subsequent call.
      #
      # Otherwise we have a situation where a :limit passed in to the
      # first call persists when no options are passed in on subsequent calls,
      # but if a different :limit is passed in that limit is applied.
      #
      # I think in this scenario one would expect no limit to be applied
      # if no options are passed in.
      #
      # When the cache_ methods are supported, those options should be
      # remembered and applied to the collection however.
      blueprint = AridCache.store.add_object_cache_configuration(object, key, nil, block)
      method_for_cached(object, key, fetch_method, method_name)
      blueprint
    end

    private

    # Dynamically define a method on the given object or class to return cached results
    def method_for_cached(object_or_class, key, fetch_method=:fetch, method_name=nil)
      method_name = ("cached_" + (method_name || key)).gsub(/[^\w\!\?]/, '_')
      method_body = <<-END
        def #{method_name}(*args, &block)
          opts = args.empty? ? {} : args.first

          proxy = AridCache::CacheProxy.new(self, #{key.inspect}, opts, &block)
          if opts[:clear] == true
            proxy.clear_cached
          else
            proxy.#{fetch_method.to_s}
          end
        end
      END
      # Get the correct class
      klass = object_or_class.is_a?(Class) ? object_or_class : object_or_class.class
      klass.class_eval(method_body, __FILE__, __LINE__)
    end
  end  
end
