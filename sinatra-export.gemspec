Gem::Specification.new do |s|
  s.name = 'sinatra-export'
  s.version = '0.9'
  
  s.authors = ['Jean-Philippe Doyle', 'Paul Asmuth']
  s.date = '2013-01-16'
  s.description = 'Export your sinatra app to a directory of static files.'
  s.summary = 'Sinatra static export.'
  s.email = 'jeanphilippe.doyle@hooktstudios.com'
  s.files = [
    'Gemfile',
    'Gemfile.lock',
    'sinatra-export.gemspec',
    'lib/sinatra/export.rb',
    'readme.md'
  ]
  s.homepage = 'http://github.com/hooktstudios/sinatra-export'
  s.license = 'MIT'
  s.required_ruby_version = '>= 1.8.7'

  s.add_runtime_dependency 'term-ansicolor'
  s.add_runtime_dependency 'sinatra'
  s.add_runtime_dependency 'sinatra-advanced-routes'
  s.add_runtime_dependency 'rack'

  s.add_development_dependency 'rack-test'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'awesome_print'
  s.add_development_dependency 'test-unit'
end
