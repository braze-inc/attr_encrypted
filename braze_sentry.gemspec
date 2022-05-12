# encoding: utf-8

$:.unshift File.expand_path('../lib', __FILE__)
require 'braze_sentry/version'

Gem::Specification.new do |s|
  s.name          = 'braze_sentry'
  s.version       = BrazeSentry::VERSION
  s.authors       = ['Jason Penny']
  s.email         = ['jason.penny@braze.com']
  s.homepage      = 'https://github.com/braze-inc/braze_sentry'
  s.licenses      = []
  s.summary       = '[summary]'
  s.description   = '[description]'

  s.files         = Dir.glob('{bin/*,lib/**/*,[A-Z]*}')
  s.platform      = Gem::Platform::RUBY
  s.require_paths = ['lib']
end
