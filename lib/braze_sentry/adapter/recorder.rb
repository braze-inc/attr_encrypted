# frozen_string_literal: true

require 'mongo'
require 'rails'

module BrazeSentry
  class Adapter
    # This class is conceptually private, do not call it directly
    class Recorder
      RETRYABLE_EXCEPTION_MESSAGES = Set.new(
        (Mongo::Error::OperationFailure::RETRY_MESSAGES + Mongo::Error::OperationFailure::WRITE_RETRY_MESSAGES).map(&:downcase)
      ).freeze

      def initialize(hub, hub_configured, transformers, exception_capturers, extras_to_tags, logger)
        @hub = hub
        @hub_configured = hub_configured
        @transformers = transformers
        @exception_capturers = exception_capturers
        @extras_to_tags = extras_to_tags
        @logger = logger
      end

      # @param [Exception] exception the captured exception object
      # @param [Hash] options additional context to send on the message to Sentry
      def capture_exception(exception, options = {})
        # Don't log to Sentry if we're in a rails console
        if defined?(Rails::Console)
          @logger.info { "Not logging exception to Sentry because Rails::Console is defined: #{exception.inspect}, #{options}" }
          return
        end

        if !@hub_configured
          if Rails.env.production? || Rails.env.test?
            @logger.info { "Not logging message to Sentry because DSN is not defined: #{exception.inspect}, #{options}" }
          elsif Rails.env.staging?
            hostname = `hostname`.strip
            if !hostname.include?('pce')
              @logger.info { "Not logging message to Sentry because DSN is not defined: #{exception.inspect}" }
            end
          end
          return
        end

        if retryable_mongo_exception?(exception)
          return
        end

        options ||= {}
        if options.frozen?
          options = options.dup
        end

        @transformers.each do |t|
          exception, options = t.transform(exception, options, @hub)
        end

        options = enhance_options_extras_to_tags(options)

        exception_captured = @exception_capturers.any? do |capturer|
          capturer.capture_exception?(exception, options)
        end
        if exception_captured
          return
        end

        @hub.capture_exception(exception, options)
      end

      # @param message [String] the message to log to Sentry
      # @param options [Hash] additional context to send on the message to Sentry
      # @param use_backtrace [Boolean] Whether or not to include the stack trace in the sentry log, note this may change the
      #   grouping
      # rubocop:disable Style/OptionalBooleanParameter
      def capture_message(message, options = {}, use_backtrace = false)
        # Don't log to Sentry if we're in a rails console
        if defined?(Rails::Console)
          @logger.info { "Not logging message to Sentry because Rails::Console is defined: #{message}, #{options}" }
          return
        end

        if !@hub_configured
          @logger.info { "Not logging message to Sentry because dns it not defined: #{message}, #{options}" }
          return
        end

        if use_backtrace
          options[:backtrace] = Kernel.caller
        end

        options ||= {}
        if options.frozen?
          options = options.dup
        end

        @transformers.each do |t|
          _, options = t.transform(nil, options, @hub)
        end

        options = enhance_options_extras_to_tags(options)

        @hub.capture_message(message, options)
      end
      # rubocop:enable Style/OptionalBooleanParameter

      def last_event_id
        return @hub.last_event_id
      end

      private

      # Returns true/false if this is a retryable Mongo exception (i.e. stepdown or similar thing)
      #
      # @param [StandardError] exception the exception passed into RavenAdapter
      # @return [Boolean]
      def retryable_mongo_exception?(exception)
        if exception.is_a?(Mongo::Error)
          error_message = exception.inspect
          if exception.is_a?(Mongo::Error::BulkWriteError)
            # these are also sometimes ignorable
            error_message += " #{exception.result.inspect}"
          end
          error_message.downcase!
          # Ignore step downs or other retryable mongo errors
          if RETRYABLE_EXCEPTION_MESSAGES.any? { |m| error_message.include?(m) }
            return true
          end
        end
        return false
      end

      # Takes relevant :extra hash items from the options hash and adds them to :tags so we can track and search for
      # errors by app group or company, etc.
      #
      # The relevant items should have been set with ::Appboy::RavenAdapter.extras_to_tags = [...]
      #
      # @param [Hash] options the options passed into RavenAdapter
      # @return [Hash] the new options hash with the relevant extras set as tags
      def enhance_options_extras_to_tags(options)
        # If we have {:extra} details of various ids, add them to tags so we can track and search for errors
        # by app group or company, etc.
        if options[:extra]
          @extras_to_tags.each do |extra_tag|
            if options[:extra][extra_tag]
              options[:tags] ||= {}
              options[:tags][extra_tag] ||= options[:extra][extra_tag]
            end
          end
        end

        return options
      end
    end
  end
end
