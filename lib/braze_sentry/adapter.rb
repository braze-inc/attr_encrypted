# frozen_string_literal: true

require 'sentry-ruby'
require 'active_support/parameter_filter'
require 'rails'

require 'braze_sentry/adapter/recorder'

module BrazeSentry
  # Wraps sentry-ruby capture_exception and capture_message calls
  class Adapter
    MUTEX = Mutex.new

    def self.set_config(errors_to_not_send_to_sentry:, extras_to_tags:,
                        deployment_environment:, default_service_name:,
                        service_dsn_lookup:, release_version:,
                        regional_name:, regional_cluster:, zone:, kubernetes:,
                        logger:)
      @errors_to_not_send_to_sentry = errors_to_not_send_to_sentry
      @extras_to_tags = extras_to_tags
      @deployment_environment = deployment_environment
      @default_service_name = default_service_name
      @service_dsn_lookup = service_dsn_lookup
      @release_version = release_version
      @regional_name = regional_name
      @regional_cluster = regional_cluster
      @zone = zone
      @kubernetes = kubernetes
      @logger = logger

      Sentry.init { |config| configure_service(config) }
      Sentry.set_tags(
        {
          region: @regional_name,
          cluster: @regional_cluster,
          az: @zone,
          kubernetes: @kubernetes,
          # Sentry only lets you have different keys set up for a tag, so we have to concatenate this all together
          pagerduty_service_tag: "#{@deployment_environment}-#{@regional_name}-#{@regional_cluster}"
        }
      )
    end

    def self.configure_service(config, service_name = nil)
      service_name ||= @default_service_name

      dsn = @service_dsn_lookup.call(service_name)
      if !dsn
        @logger.info "No Sentry DSN for service_name '#{service_name.inspect}' in deployment environment '#{@deployment_environment}': '#{dsn.inspect}'"
        dsn = @service_dsn_lookup.call(@default_service_name)
      end

      config.dsn = dsn

      config.enabled_environments = ['staging', 'production', 'development']
      config.environment = @deployment_environment
      config.release = @release_version

      # this is more similar to the previous sentry-raven behavior
      config.send_default_pii = true

      # https://docs.sentry.io/platforms/ruby/guides/rails/configuration/filtering/#filtering-error-events
      if Rails.application&.config&.filter_parameters
        pfilter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
        config.before_send = lambda do |event, _hint|
          pfilter.filter(event.to_hash)
        end
      end

      config.excluded_exceptions += @errors_to_not_send_to_sentry

      # sentry-rails has some exceptions ignored by default from their side
      # We've specifically been bitten by the fact that they ignore CSRF issues by default, so override that
      config.excluded_exceptions -= ['ActionController::InvalidAuthenticityToken']

      # send events synchronously, like sentry-raven did
      # this otherwise defaults to worker threads matching the number of processors
      # and sends async
      config.background_worker_threads = 0

      # sentry-ruby adds session support. We don't want this because it's billions of events per day
      config.auto_session_tracking = false

      # this will update config.errors like sentry-raven did
      config.sending_allowed?
    end

    def self.register_transformer(transformer)
      transformers << transformer
    end

    private_class_method def self.transformers
      return @transformers ||= Set.new
    end

    def self.register_exception_capturer(capturer)
      exception_capturers << capturer
    end

    private_class_method def self.exception_capturers
      return @exception_capturers ||= Set.new
    end

    # Rescues all exceptions so if someone has a call like
    #   BrazeSentry::Adapter.capture_message("hi there #{undefined_variable}")
    # that the code path doesn't cause the job to fail
    def self.with_rescued_exceptions(service_name = nil)
      service_name ||= @default_service_name

      begin
        hub, configured = get_hub_for_service(service_name)
        recorder = Recorder.new(
          hub,
          configured,
          transformers,
          exception_capturers,
          @extras_to_tags || [].freeze,
          @logger
        )

        yield recorder
      rescue StandardError => e
        @logger.error { "#{self} got error #{e.inspect} from #{e.backtrace}" }
      end
    end

    # @param [String] service_name
    # @return [Sentry::Hub, Boolean] the instance and whether or not it has a DSN set
    def self.get_hub_for_service(service_name)
      if @hub_instances.nil?
        MUTEX.synchronize do
          @hub_instances ||= {}
        end
      end

      hub = @hub_instances[service_name]
      configured = true

      if !hub
        MUTEX.synchronize do
          hub = @hub_instances[service_name]
          if !hub
            configured = false

            if service_name == @default_service_name
              hub = Sentry.get_main_hub
            else
              config = Sentry.configuration.dup
              configure_service(config, service_name)

              client = Sentry::Client.new(config)

              hub = Sentry::Hub.new(client, Sentry.get_current_scope.dup)
            end

            if !hub.configuration.errors&.include?('DSN not set or not valid')
              @hub_instances[service_name] = hub
              configured = true
            end
          end
        end
      end

      return hub, configured
    end
  end
end
