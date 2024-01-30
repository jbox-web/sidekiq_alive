# frozen_string_literal: true

require_relative "lib/sidekiq_alive/version"

Gem::Specification.new do |s|
  s.name        = "sidekiq_alive"
  s.version     = SidekiqAlive::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Andrejs Cunskis", "Artur Pañach"]
  s.email       = ["andrejs.cunskis@gmail.com", "arturictus@gmail.com"]
  s.homepage    = "https://github.com/arturictus/sidekiq_alive"
  s.summary     = "Liveness probe for sidekiq on Kubernetes deployments."
  s.description = "SidekiqAlive offers a solution to add liveness probe of a Sidekiq instance."
  s.license     = "MIT"

  s.metadata = {
    "homepage_uri" => s.homepage,
    "source_code_uri" => s.homepage,
    "changelog_uri" => "#{s.homepage}/releases",
    "documentation_uri" => "#{s.homepage}/blob/v#{s.version}/README.md",
    "bug_tracker_uri" => "#{s.homepage}/issues",
  }

  s.required_ruby_version = ">= 3.0.0"

  s.files = Dir["README.md", "lib/**/*"]

  s.add_runtime_dependency("rack", ">= 2.2.4")
  s.add_runtime_dependency("rackup")
  s.add_runtime_dependency("sidekiq", ">= 5", "< 8")
  s.add_runtime_dependency("webrick", ">= 1", "< 2")

  s.add_development_dependency("debug", "~> 1.6")
  s.add_development_dependency("rack-test", "~> 2.1.0")
  s.add_development_dependency("rake", "~> 13.0")
  s.add_development_dependency("rspec")
  s.add_development_dependency("rspec-sidekiq")
  s.add_development_dependency("rubocop-shopify")
  s.add_development_dependency("ruby-lsp")
  s.add_development_dependency("simplecov")
  s.add_development_dependency("simplecov-cobertura")
  s.add_development_dependency("solargraph")
end
