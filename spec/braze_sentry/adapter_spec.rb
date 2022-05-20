# frozen_string_literal: true

RSpec.describe BrazeSentry::Adapter do
  class self::ExampleTransformer
    def self.transform(exception, options, _sentry_hub)
      return exception, options
    end
  end

  class self::ExampleExceptionCapturer
    def self.capture_exception?(_exception, _options)
      return false
    end
  end

  before(:each) do
    BrazeSentry::Adapter.set_config(
      errors_to_not_send_to_sentry: [],
      extras_to_tags: [
        :app_group_id,
        :company_id
      ],
      deployment_environment: 'unknown',
      default_service_name: 'default',
      service_dsn_lookup: ->(_) { 'https://invalid-key-for-testing@sentry.example.com/invalid-id-for-testing' },
      release_version: 'deadbeef',
      regional_name: 'us-east-1',
      regional_cluster: '01',
      zone: nil,
      kubernetes: 'false',
      logger: logger
    )
  end

  let(:message) { 'foo' }
  let(:ex) { StandardError.new(message) }
  let(:original_opts) { { some: 'options', tags: {} } }
  let(:opts_expected) { original_opts.dup }
  let(:logger) { double.as_null_object }

  context 'self#with_rescued_exceptions' do
    it 'swallows exceptions' do
      expect(logger).to receive(:error)

      described_class.with_rescued_exceptions do
        raise StandardError, 'this will fail the job if it bubbles out'
      end
    end

    context 'yielded recorder' do
      before(:each) do
        # with_rescued_exceptions hides some errors in expectations
        expect(logger).not_to receive(:error)
      end

      context '#capture_message' do
        it 'passes it along to Sentry' do
          expect_any_instance_of(Sentry::Hub).to receive(:capture_message).with(message, opts_expected)

          described_class.with_rescued_exceptions do |hub|
            hub.capture_message(message, original_opts)
          end
        end

        it 'augments tags with extras of ids' do
          extra = { app_group_id: 'a', company_id: 'b' }
          opts = { extra: extra, backtrace: anything }
          opts_expected = opts.merge(tags: extra)
          expect_any_instance_of(Sentry::Hub).to receive(:capture_message).with(message, opts_expected)
          described_class.with_rescued_exceptions do |hub|
            hub.capture_message(message, opts)
          end
        end

        context 'with backtrace' do
          it 'passes it along to Sentry' do
            expect_any_instance_of(Sentry::Hub).to receive(:capture_message).with(message, hash_including(**opts_expected, backtrace: Array))

            described_class.with_rescued_exceptions do |hub|
              hub.capture_message(message, original_opts, true)
            end
          end
        end

        context 'transformers' do
          after(:all) { BrazeSentry::Adapter.remove_instance_variable(:@transformers) }

          it '#transform gets called' do
            BrazeSentry::Adapter.register_transformer(self.class::ExampleTransformer)

            expect(self.class::ExampleTransformer).to receive(:transform).and_call_original

            described_class.with_rescued_exceptions do |hub|
              hub.capture_exception(ex, original_opts)
            end
          end
        end

        context 'exception_capturers' do
          before(:all) { BrazeSentry::Adapter.register_exception_capturer(self.class::ExampleExceptionCapturer) }
          after(:all) { BrazeSentry::Adapter.remove_instance_variable(:@exception_capturers) }

          it '#capture_exception? gets called' do
            expect(self.class::ExampleExceptionCapturer).to receive(:capture_exception?)

            described_class.with_rescued_exceptions do |hub|
              hub.capture_exception(ex, original_opts)
            end
          end

          context 'when #capture_exception? returns false' do
            it 'the exception is sent to Sentry' do
              allow(self.class::ExampleExceptionCapturer).to receive(:capture_exception?).and_return(false)

              expect_any_instance_of(Sentry::Hub).to receive(:capture_exception)

              described_class.with_rescued_exceptions do |hub|
                hub.capture_exception(ex, original_opts)
              end
            end
          end

          context 'when #capture_exception? returns true' do
            it 'the exception is NOT sent to Sentry' do
              allow(self.class::ExampleExceptionCapturer).to receive(:capture_exception?).and_return(true)

              expect_any_instance_of(Sentry::Hub).not_to receive(:capture_exception)

              described_class.with_rescued_exceptions do |hub|
                hub.capture_exception(ex, original_opts)
              end
            end
          end
        end
      end

      context '#capture_exception' do
        it 'passes it along to Sentry' do
          expect_any_instance_of(Sentry::Hub).to receive(:capture_exception).with(ex, opts_expected)

          described_class.with_rescued_exceptions do |hub|
            hub.capture_exception(ex, original_opts)
          end
        end

        it 'augments tags with extras of ids' do
          extra = { app_group_id: 'a', company_id: 'b' }
          opts = { extra: extra }

          opts_expected = opts.merge(tags: extra)

          expect_any_instance_of(Sentry::Hub).to receive(:capture_exception).with(ex, opts_expected)

          described_class.with_rescued_exceptions do |hub|
            hub.capture_exception(ex, opts)
          end
        end

        context 'when the error is a Mongo::Error::OperationFailure' do
          context 'and the error is a retryable error' do
            let(:ex) do
              Mongo::Error::OperationFailure.new(Mongo::Error::OperationFailure::RETRY_MESSAGES.first)
            end

            it 'does not send' do
              expect_any_instance_of(Sentry::Hub).to_not receive(:capture_exception)
              described_class.with_rescued_exceptions do |hub|
                hub.capture_exception(ex, original_opts)
              end
            end
          end
        end

        context 'when the error is a Mongo::Error::BulkWriteError' do
          context 'and the error in result is a retryable error' do
            let(:ex) do
              Mongo::Error::BulkWriteError.new(Mongo::Error::OperationFailure::RETRY_MESSAGES.first)
            end

            it 'does not send' do
              expect_any_instance_of(Sentry::Hub).to_not receive(:capture_exception)
              described_class.with_rescued_exceptions do |hub|
                hub.capture_exception(ex, original_opts)
              end
            end
          end
        end

        context 'transformers' do
          after(:all) { BrazeSentry::Adapter.remove_instance_variable(:@transformers) }

          it '#transform gets called' do
            BrazeSentry::Adapter.register_transformer(self.class::ExampleTransformer)

            expect(self.class::ExampleTransformer).to receive(:transform).and_call_original

            described_class.with_rescued_exceptions do |hub|
              hub.capture_message(ex.to_s, original_opts)
            end
          end
        end
      end

      context 'last_event_id' do
        it 'should delegate to Sentry::Hub.last_event_id' do
          expect_any_instance_of(Sentry::Hub).to receive(:last_event_id).and_return('fake last_event_id')

          sentry_event_id = nil

          described_class.with_rescued_exceptions do |r|
            sentry_event_id = r.last_event_id
          end

          expect(sentry_event_id).to eq('fake last_event_id')
        end
      end
    end
  end

  context 'self#get_hub_for_service' do
    before(:each) do
      # with_rescued_exceptions hides some errors in expectations
      expect(logger).not_to receive(:error)
    end

    let(:service_name) { 'default' }

    it 'should use a mutex' do
      described_class.instance_variable_set(:@hub_instances, nil)

      called = 'Mutex *not* called'
      allow(described_class::MUTEX).to receive(:synchronize) do |_instance, &blk|
        called = 'Mutex was called'
        blk.call
      end

      described_class.get_hub_for_service(service_name)

      expect(called).to eq('Mutex was called')
    end

    context 'the [configured] return value' do
      it "should be true for the 'default' service" do
        instance, configured = described_class.get_hub_for_service(service_name)

        expect(instance).to be_a(Sentry::Hub)
        expect(configured).to be(true)
      end

      it 'should be false for an unconfigured service and the default service is also unconfigured',
         skip: 'DSN lookup falls back to the DSN for default_service_name (which is configured)' do
        broken, configured = described_class.get_hub_for_service('an invalid service with no DSN')

        expect(broken).to be_a(Sentry::Hub)
        expect(configured).to be(false)
      end
    end

    context 'when no arguments are provided' do
      it "should return the instance configured for the 'default' service" do
        instance, = described_class.get_hub_for_service(service_name)

        expect(instance.configuration.errors).to eq(["Not configured to send/capture in environment 'unknown'"])
      end
    end

    context 'when called multiple times' do
      it 'should return an existing instance' do
        first, = described_class.get_hub_for_service(service_name)
        second, = described_class.get_hub_for_service(service_name)

        expect(second).to be(first)
      end
    end

    context 'when a service is provided' do
      it 'should return an instance configured for that service' do
        default_instance, = described_class.get_hub_for_service(service_name)
        prototransactional_messaging_instance, = described_class.get_hub_for_service('prototransactional-messaging')
        transactional_messaging_instance, = described_class.get_hub_for_service('transactional-messaging')

        expect(default_instance).to be_a(Sentry::Hub)
        expect(prototransactional_messaging_instance).to be_a(Sentry::Hub)
        expect(transactional_messaging_instance).to be_a(Sentry::Hub)

        expect(default_instance).to_not be(prototransactional_messaging_instance)
        expect(prototransactional_messaging_instance).to_not be(transactional_messaging_instance)
      end
    end

    context 'when the generated instance is not fully configured' do
      it 'should return a default configured instance' do
        broken, = described_class.get_hub_for_service('an invalid service with no DSN')
        default, = described_class.get_hub_for_service('default')

        expect(broken.configuration.dsn.project_id).to eq(
          default.configuration.dsn.project_id
        )
      end
    end
  end

  context 'self#configure_service' do
    before(:each) do
      # with_rescued_exceptions hides some errors in expectations
      expect(logger).not_to receive(:error)
    end

    let(:config) { Sentry::Configuration.new }

    it 'should configure a configuration' do
      described_class.configure_service(config)

      expect(config.errors).to eq(["Not configured to send/capture in environment 'unknown'"])
    end
  end

  context 'testing harness' do
    before(:each) do
      # with_rescued_exceptions hides some errors in expectations
      expect(logger).not_to receive(:error)
    end

    let(:non_default_service) { 'nondefault' }

    it 'should cache instances' do
      first, = described_class.get_hub_for_service(non_default_service)
      second, = described_class.get_hub_for_service(non_default_service)

      expect(second).to be(first)

      described_class.instance_variable_set(:@hub_instances, nil)

      third, = described_class.get_hub_for_service(non_default_service)

      expect(third).to_not be(first)
    end
  end
end
