# frozen_string_literal: true

RSpec.describe BrazeSentry::Sidekiq::ErrorHandler do
  class self::ExampleSidekiqJob
    def self.service_name
      nil
    end
  end

  let(:handler) { described_class.new }
  let(:exception) { StandardError.new }
  let(:context) { {} }
  let(:sidekiq_job_class) { self.class::ExampleSidekiqJob }
  let(:sidekiq_shard_index) { 42 }
  let(:code_owner_for_sidekiq_job_class) { '@Appboy/some-team' }
  let(:increment_retry_metric) { double }

  before :each do
    Sentry.init
    described_class.set_config(
      sidekiq_job_class: -> { sidekiq_job_class },
      sidekiq_shard_index: -> { sidekiq_shard_index },
      code_owner_for_sidekiq_job_class: ->(_sidekiq_job_class) { code_owner_for_sidekiq_job_class },
      increment_retry_metric: increment_retry_metric
    )

    allow(described_class).to receive(:include_code_ownership_data?).and_return(true)
    allow(increment_retry_metric).to receive(:call)
  end

  context '#call' do
    it 'sets the scope transaction name to JobCorruption if an error is encountered' do
      context_filter = instance_double(::Sentry::Sidekiq::ContextFilter)
      expect(::Sentry::Sidekiq::ContextFilter).to receive(:new).and_return(context_filter)
      allow(context_filter).to receive(:transaction_name)
      expect(context_filter).to receive(:filtered).and_raise
      allow(Sentry.get_current_scope).to receive(:set_transaction_name)

      expect(Sentry.get_current_scope).to receive(:set_transaction_name).with('Sidekiq/JobCorruption')

      handler.call(exception, context)
    end

    context 'captures exceptions using BrazeSentry::Adapter' do
      let(:mock_hub) { double('mock_hub') }

      before(:each) { expect(BrazeSentry::Adapter).to receive(:with_rescued_exceptions).and_yield(mock_hub) }

      it 'logs to Sentry' do
        expect(mock_hub).to receive(:capture_exception)

        handler.call(exception, context)
      end

      it 'sets the shard as :extra' do
        expect(mock_hub).to receive(:capture_exception).with(
          exception,
          hash_including(
            extra: hash_including(
              shard: sidekiq_shard_index
            )
          )
        )

        handler.call(exception, context)
      end

      it 'sets the code_owner as :extra' do
        expect(mock_hub).to receive(:capture_exception).with(
          exception,
          hash_including(
            extra: hash_including(
              code_owner: code_owner_for_sidekiq_job_class
            )
          )
        )

        handler.call(exception, context)
      end
    end

    it 'passes sidekiq_job_class.service_name to Adapter.with_rescued_exceptions' do
      other_service_name = 'other'

      allow(self.class::ExampleSidekiqJob).to receive(:service_name).and_return(other_service_name)
      expect(BrazeSentry::Adapter).to receive(:with_rescued_exceptions).with(other_service_name)

      handler.call(exception, context)
    end

    it 'calls increment_retry_metric lambda with include_code_ownership_data and the exception' do
      expect(increment_retry_metric).to receive(:call).with(true, instance_of(StandardError))
      handler.call(exception, context)
    end
  end
end
