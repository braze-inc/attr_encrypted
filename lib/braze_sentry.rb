# frozen_string_literal: true

require 'braze_sentry/version'
require 'braze_sentry/adapter'
require 'braze_sentry/teams'
require 'braze_sentry/sidekiq/error_handler'

require 'sentry-rails'
require 'sentry-ruby'
require 'sentry-sidekiq'

# BrazeSentry is a wrapper around sentry.io error tracking
module BrazeSentry
end
