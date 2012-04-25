$:.unshift File.expand_path("../lib", __FILE__)
require "claw/builder"

Gem::Specification.new do |gem|
  gem.name    = "claw-builder"
  gem.version = Claw::Builder::VERSION

  gem.author      = "Ken Robertson"
  gem.email       = "ken@paas.io"
  gem.homepage    = "http://paas.io/"
  gem.summary     = "Build software in the cloud"
  gem.description = gem.summary
  gem.executables = "claw-builder"

  gem.files = Dir["**/*"].select { |d| d =~ %r{^(README|bin/|ext/|lib/)} }

  gem.add_dependency "rest-client",     "~> 1.6.7"
  gem.add_dependency "socketio-client", "~> 0.0.2"
  gem.add_dependency "thor",            "~> 0.14.6"
  gem.add_dependency "json"
end
