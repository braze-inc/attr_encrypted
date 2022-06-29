# frozen_string_literal: true

module BrazeSentry
  # These teams are defined in the sentry.io UI.
  #
  # These values can be passed to #capture_exception and #capture_message in the options to auto-assign alerts to a team,
  # such as:
  #   BrazeSentry::Adapter.with_rescued_exceptions do |rec|
  #     rec.capture_message(
  #       "some message",
  #       { extra: { team: BrazeSentry::Teams::CHANNELS } }
  #     )
  #   end
  class Teams
    APPLICATION_INFRASTRUCTURE = 'app_inf'
    CHANNELS = 'channels'
    CORE_MESSAGING = 'core_messaging'
    CURRENTS = 'currents'
    DASHBOARD_INFRASTRUCTURE = 'dashboard_inf'
    DATA_LAKE = 'data_lake'
    DEVOPS = 'devops'
    EMAIL_COMPOSITION = 'email_composition'
    EMAIL_INFRASTRUCTURE = 'email_infrastructure'
    IAM = 'iam'
    IN_MEMORY_DB = 'in_memory_db'
    INGESTION = 'ingestion'
    INTELLIGENCE = 'intelligence'
    INTERNAL_TOOLS = 'internal_tools'
    MESSAGING_AND_AUTOMATION = 'messaging_automation'
    PARTNERSHIPS = 'partnerships'
    REPORTING = 'reporting'
    SECURITY = 'security'
    SMS = 'sms'
  end
end
