require 'i18n'
require 'i18n/backend/transliterator'
require 'i18n/backend/base'
require 'i18n/backend/http/version'
require 'i18n/backend/http/etag_http_client'
require 'i18n/backend/http/null_cache'
require 'i18n/backend/http/lru_cache'
require 'socket'

module I18n
  module Backend
    class Http
      include ::I18n::Backend::Base

      def initialize(options)
        @options = {
          :http_open_timeout => 1,
          :http_read_timeout => 1,
          :polling_interval => 10*60,
          :cache => NullCache.new,
          :poll => true,
          :exception_handler => lambda{|e| $stderr.puts e },
          :memory_cache_size => 10,
        }.merge(options)

        @http_client = EtagHttpClient.new(@options)
        @translations = LRUCache.new(@options[:memory_cache_size])
        start_polling if @options[:poll]
      end

      def available_locales
        @translations.keys.map(&:to_sym).select { |l| l != :i18n }
      end

      def stop_polling
        @stop_polling = true
      end

      protected

      def start_polling
        Thread.new do
          until @stop_polling
            sleep(@options[:polling_interval])
            update_caches
          end
        end
      end

      def lookup(locale, key, scope = [], options = {})
        key = ::I18n.normalize_keys(locale, key, scope, options[:separator])[1..-1].join('.')
        lookup_key translations(locale), key
      end

      def translations(locale)
        @translations[locale] ||= (
          translations_from_cache(locale) ||
          download_and_cache_translations(locale)
        )
      end

      def update_caches
        @translations.keys.each do |locale|
          if @options[:cache].is_a?(NullCache)
            download_and_cache_translations(locale)
          else
            locked_update_cache(locale)
          end
        end
      end

      def locked_update_cache(locale)
        unless update_cache(locale) { download_and_cache_translations(locale) }
          update_memory_cache_from_cache(locale)
        end
      end

      def update_cache(locale)
        cache = @options.fetch(:cache)
        key = "i18n/backend/http/locked_update_caches/#{locale}"
        me = "#{Socket.gethostname}-#{Process.pid}-#{Thread.current.object_id}"
        if current = cache.read(key)
          if current == me
            try = false  # I am responsible, renew expiration
          else
            return # someone else is responsible, do not touch
          end
        else
          try = true # nobody is responsible, try to get responsibility
        end

        return unless cache.write(key, me, expires_in: (@options[:polling_interval] * 3).ceil, unless_exist: try)

        yield
        true
      end

      def update_memory_cache_from_cache(locale)
        @translations[locale] = translations_from_cache(locale)
      end

      def translations_from_cache(locale)
        @options[:cache].read(cache_key(locale))
      end

      def cache_key(locale)
        "i18n/backend/http/translations/#{locale}"
      end

      def download_and_cache_translations(locale)
        @http_client.download(path(locale)) do |result|
          translations = parse_response(result)
          @options[:cache].write(cache_key(locale), translations)
          @translations[locale] = translations
        end
      rescue => e
        @options[:exception_handler].call(e)
        @translations[locale] = {} # do not write distributed cache
      end

      def parse_response(body)
        raise "implement parse_response"
      end

      def path(locale)
        raise "implement path"
      end

      # hook for extension with other resolution method
      def lookup_key(translations, key)
        translations[key]
      end
    end
  end
end
