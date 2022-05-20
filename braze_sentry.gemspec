# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'braze_sentry/version'

Gem::Specification.new do |s|
  s.name          = 'braze_sentry'
  s.version       = BrazeSentry::VERSION
  s.authors       = ['Jason Penny']
  s.email         = ['jason.penny@braze.com']
  s.homepage      = 'https://github.com/braze-inc/braze_sentry'
  s.licenses      = []
  s.summary       = 'Wrapper around sentry.io error tracking'
  s.description   = 'Wrapper around sentry.io error tracking.'
  s.required_ruby_version = '>= 2.7.3'

  s.files         = Dir.glob('{bin/*,lib/**/*,[A-Z]*}')
  s.platform      = Gem::Platform::RUBY
  s.require_paths = ['lib']

  s.add_dependency 'mongo'
  s.add_dependency 'rails'
  s.add_dependency 'sentry-rails', '5.3.0'
  s.add_dependency 'sentry-ruby', '5.3.0'
  s.add_dependency 'sentry-sidekiq', '5.3.0'

  s.add_development_dependency 'byebug'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'rubocop-rspec'
end
