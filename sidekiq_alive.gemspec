# frozen_string_literal: true

require_relative 'lib/sidekiq_alive/version'

Gem::Specification.new do |s|
  s.name        = 'sidekiq_alive'
  s.version     = SidekiqAlive::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Andrejs Cunskis', 'Artur Pañach']
  s.email       = ['andrejs.cunskis@gmail.com', 'arturictus@gmail.com']
  s.homepage    = 'https://github.com/arturictus/sidekiq_alive'
  s.summary     = 'Liveness probe for sidekiq on Kubernetes deployments.'
  s.description = 'SidekiqAlive offers a solution to add liveness probe of a Sidekiq instance.'
  s.license     = 'MIT'

  s.metadata = {
    'homepage_uri' => s.homepage,
    'source_code_uri' => s.homepage,
    'changelog_uri' => "#{s.homepage}/releases",
    'documentation_uri' => "#{s.homepage}/blob/v#{s.version}/README.md",
    'bug_tracker_uri' => "#{s.homepage}/issues",
  }

  s.required_ruby_version = '>= 3.2.0'

  s.files = Dir['README.md', 'LICENSE', 'lib/**/*.rb']

  s.add_dependency('rack', '>= 2.2.4')
  s.add_dependency('rackup')
  s.add_dependency('sidekiq', '>= 7', '< 9')
  s.add_dependency('webrick', '>= 1', '< 2')
  s.add_dependency('zeitwerk', '~> 2.6.0')
end
