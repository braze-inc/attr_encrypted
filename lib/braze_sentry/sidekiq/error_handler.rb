# frozen_string_literal: true

require 'sentry-sidekiq'

module BrazeSentry
  module Sidekiq
    # Supplements the default Sidekiq ErrorHandler to use BrazeSentry::Adapter,
    # include code ownership, and emit metrics.
    class ErrorHandler < ::Sentry::Sidekiq::ErrorHandler
      def call(exception, context)
        if !::Sentry.initialized?
          return
        end

        contexts = {}
        scope = ::Sentry.get_current_scope
        begin
          context_filter = ::Sentry::Sidekiq::ContextFilter.new(context)

          if !scope.transaction_name
            scope.set_transaction_name(context_filter.transaction_name)
          end

          contexts[:sidekiq] = context_filter.filtered
        rescue StandardError
          if !scope.transaction_name
            scope.set_transaction_name('Sidekiq/JobCorruption')
          end
        end

        if ::Sentry.configuration.sidekiq.report_after_job_retries && retryable?(context)
          retry_count = context.dig(:job, 'retry_count')
          if retry_count.nil? || retry_count < retry_limit(context) - 1
            return
          end
        end

        extra = {}

        sidekiq_job_class = self.class.sidekiq_job_class
        extra[:shard] = self.class.sidekiq_shard_index

        if self.class.include_code_ownership_data?
          extra[:code_owner] = self.class.code_owner_for_sidekiq_job_class(sidekiq_job_class)
        end

        service_name = sidekiq_job_class.try(:service_name)
        BrazeSentry::Adapter.with_rescued_exceptions(service_name) do |hub|
          hub.capture_exception(
            exception,
            contexts: contexts,
            hint: { background: false },
            extra: extra
          )
        end

        self.class.increment_retry_metric(exception)
      end

      def self.include_code_ownership_data?
        return !Rails.env.test?
      end

      def self.set_config(sidekiq_job_class:, sidekiq_shard_index:,
                          code_owner_for_sidekiq_job_class:, increment_retry_metric:)
        @sidekiq_job_class = sidekiq_job_class
        @sidekiq_shard_index = sidekiq_shard_index
        @code_owner_for_sidekiq_job_class = code_owner_for_sidekiq_job_class
        @increment_retry_metric = increment_retry_metric
      end

      def self.sidekiq_job_class
        if @sidekiq_job_class.nil?
          return nil
        end

        return @sidekiq_job_class.call
      end

      def self.sidekiq_shard_index
        if @sidekiq_shard_index.nil?
          return nil
        end

        return @sidekiq_shard_index.call
      end

      def self.code_owner_for_sidekiq_job_class(sidekiq_job_class)
        if @code_owner_for_sidekiq_job_class.nil?
          return 'UNKNOWN'
        end

        return @code_owner_for_sidekiq_job_class.call(sidekiq_job_class)
      end

      def self.increment_retry_metric(exception)
        if @increment_retry_metric.nil?
          return nil
        end

        return @increment_retry_metric.call(include_code_ownership_data?, exception)
      end
    end
  end
end

Sidekiq.configure_server do |config|
  config.error_handlers.delete_if { |x| x.instance_of?(::Sentry::Sidekiq::ErrorHandler) }
  config.error_handlers << BrazeSentry::Sidekiq::ErrorHandler.new
end
