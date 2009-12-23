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
      if key =~ /(.*)_count$/
        if block_given?
          define(object, key, opts, &block)
        elsif AridCache.store.has?(object, $1)
          method_for_cached(object, $1, :fetch_count, key)
        elsif object.respond_to?(key)
          define(object, key, opts, :fetch_count)
        elsif object.respond_to?($1)
          define(object, $1, opts, :fetch_count, key)
        else
          raise ArgumentError.new("#{object} doesn't respond to #{key} or #{$1}!  Cannot dynamically create query to get the count, please call with a block.")
        end 
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
    # @return an AridCache::Store::Item.
    def define(object, key, opts, fetch_method=:fetch, method_name=nil, &block)
      if !block_given? && !object.respond_to?(key)
        raise ArgumentError.new("#{object} doesn't respond to #{key}!  Cannot dynamically create a block for your cache item.")
      end
      
      blueprint = if block_given?
        AridCache.store.add(object, key, Proc.new { |object, key| block.call } , opts)
      else
        AridCache.store.add(object, key, Proc.new { |object, key| object.send(key) }, opts)
      end
      method_for_cached(object, key, fetch_method, method_name)
      blueprint
    end

    private

    def method_for_cached(object, key, fetch_method=:fetch, method_name=nil)
      method_name = "cached_" + (method_name || key)
      if object.is_a?(Class)
        (class << object; self; end).instance_eval do
          define_method(method_name) do |*args|
            opts = args.empty? ? {} : args.first
            AridCache.cache.send(fetch_method, self, key, AridCache.store.find(self, key), opts)
          end
        end
      else
        object.class_eval do
          define_method(method_name) do |*args|
            opts = args.empty? ? {} : args.first
            AridCache.cache.send(fetch_method, self, key, AridCache.store.find(self, key), opts)
          end
        end
      end
    end
  end  
end
