# sinatra-static

> Exports your Sinatra app to static files. Get requests and response-status 200 only (no redirects).

Depends on [sinatra-advanced-routes](https://github.com/rkh/sinatra-advanced-routes)

## Installation

Add `sinatra-static` to your Gemfile

    gem 'sinatra-static', '>= 0.1.1'

## Usage

```ruby
builder = SinatraStatic.new(App)
builder.build!('public/')
```

## Getting started

Sample Sinatra application building static pages :

```ruby
require 'sinatra'
require 'sinatra/advanced_routes'
require 'sinatra_static'

class App < Sinatra::Base

    register Sinatra::AdvancedRoutes

    get '/' do    
      "homepage"
    end

    get '/contact' do
      "contact"
    end

end

builder = SinatraStatic.new(App)
builder.build!('public/')
```

Running your app ex. `ruby app.rb` will automatically generate theses files :

    public/index.html              -> "homepage"
    public/contact/index.html      -> "contact"
