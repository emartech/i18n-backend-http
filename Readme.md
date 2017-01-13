Rails I18n Backend for Http APIs with etag-aware distributed background polling and lru-memory+[memcache] caching.<br/>
Very few request, always up to date + fast.

Install
=======

```Bash
gem install i18n-backend-http
```

Usage
=====

```Ruby
class MyBackend < I18n::Backend::Http
  def initialize(options={})
    super({
      host:  "https://api.host.com",
      cache: Rails.cache,
      http_open_timeout: 5, # default: 1
      http_read_timeout: 5, # default: 1
      # exception_handler:  lambda{|e| Rails.logger.error e },
      # memory_cache_size: ??, # default: 10 locales
    }.merge(options))
  end

  def parse_response(body)
    JSON.load(body).fetch("translations")
  end

  def path(locale)
    "/path/to/api/#{locale}.json"
  end
end

I18n.backend = MyBackend.new
```

### Polling
Tries to update all used translations every 10 minutes (using ETag and :cache), can be stopped via `I18n.backend.stop_polling`.<br/>
If a :cache is given, all backends pick one master to do the polling, all others refresh from :cache

```Ruby
I18n.backend = MyBackend.new(polling_interval: 30.minutes, cache: Rails.cache)

I18n.t('some.key') == "Old value"
# change in backend + wait 30 minutes
I18n.t('some.key') == "New value"
```

### :cache
If you pass `cache: Rails.cache`, translations will be loaded from cache and updated in the cache.<br/>
The cache **MUST** support :unless_exist MemCacheStore + LibmemcachedStore + Dalli + ActiveSupport::Cache::MemoryStore (4+) work.

### Exceptions
To handle http exceptions provide e.g. `exception_handler: -> (e) { puts e }` (prints to stderr by default).

### Limited memory cache
The backend stores the 10 least recently used locales in memory, change via `memory_cache_size: 100`

### Fallback
If the http backend is down, it does not translate, but also does not constantly try to query -> your app is untranslated but not down.</br>
You should either use `:default` for all `I18n.t` or use a Chain, so when http is down e.g. english is used.

```Ruby
I18n.backend = I18n::Backend::Chain.new(
  MyBackend.new(options),
  I18n::Backend::Simple.new
)
```


TODO
====
 - available_locales is not implemented, since we did not need it
 - `reload` -> all caches should be cleared

Author
======
[Michael Grosser](http://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT<br/>
[![Build Status](https://travis-ci.org/grosser/i18n-backend-http.png)](https://travis-ci.org/grosser/i18n-backend-http)
