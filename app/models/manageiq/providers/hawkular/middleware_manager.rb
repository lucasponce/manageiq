# TODO: remove the module and just make this:
# class ManageIQ::Providers::Hawkular::MiddlewareManager < ManageIQ::Providers::MiddlewareManager
module ManageIQ::Providers
  class Hawkular::MiddlewareManager < ManageIQ::Providers::MiddlewareManager
    require_nested :AlertManager
    require_nested :AlertProfileManager
    require_nested :EventCatcher
    require_nested :LiveMetricsCapture
    require_nested :MiddlewareDeployment
    require_nested :MiddlewareServer
    require_nested :RefreshParser
    require_nested :RefreshWorker
    require_nested :Refresher

    include AuthenticationMixin

    DEFAULT_PORT = 80
    default_value_for :port, DEFAULT_PORT

    has_many :middleware_servers, :foreign_key => :ems_id, :dependent => :destroy
    has_many :middleware_deployments, :foreign_key => :ems_id, :dependent => :destroy

    def verify_credentials(_auth_type = nil, options = {})
      begin

        # As the connect will only give a handle
        # we verify the credentials via an actual operation
        connect(options).list_feeds
      rescue => err
        raise MiqException::MiqInvalidCredentialsError, err.message
      end

      true
    end

    # Inventory

    def self.raw_connect(hostname, port, username, password)
      require 'hawkular/hawkular_client'
      url = URI::HTTP.build(:host => hostname, :port => port.to_i, :path => '/hawkular/inventory').to_s
      ::Hawkular::Inventory::InventoryClient.new(url, :username => username, :password => password)
    end

    def connect(_options = {})
      self.class.raw_connect(hostname,
                             port,
                             authentication_userid('default'),
                             authentication_password('default'))
    end

    def feeds
      with_provider_connection(&:list_feeds)
    end

    def eaps(feed)
      with_provider_connection do |connection|
        connection.list_resources_for_type(feed, 'WildFly Server', true)
      end
    end

    def child_resources(eap_parent)
      with_provider_connection do |connection|
        connection.list_child_resources(eap_parent)
      end
    end

    def metrics_resource(resource)
      with_provider_connection do |connection|
        connection.list_metrics_for_resource(resource)
      end
    end

    def self.raw_metrics_connect(hostname, port, username, password)
      require 'hawkular/hawkular_client'
      url         = URI::HTTP.build(:host => hostname, :port => port.to_i, :path => '/hawkular/metrics').to_s
      options     = {}
      credentials = {
        :username => username,
        :password => password
      }
      ::Hawkular::Metrics::Client.new(url, credentials, options)
    end

    def metrics_connect
      self.class.raw_metrics_connect(hostname,
                                     port,
                                     authentication_userid('default'),
                                     authentication_password('default'))
    end

    def self.raw_operations_connect(hostname, port, username, password)
      require 'hawkular/hawkular_client'
      host_port = URI::HTTP.build(:host => hostname, :port => port.to_i).to_s
      host_port.sub!('http://', '') # Api can't internally deal with the schema
      credentials = {:username => username, :password => password}
      ::Hawkular::Operations::OperationsClient.new(:host => host_port, :credentials => credentials)
    end

    def operations_connect
      self.class.raw_operations_connect(hostname,
                                        port,
                                        authentication_userid('default'),
                                        authentication_password('default'))
    end

    def reload_middleware_server(ems_ref)
      run_generic_operation(:Reload, ems_ref)
    end

    def stop_middleware_server(ems_ref)
      run_generic_operation(:Shutdown, ems_ref)
    end

    def self.raw_alerts_connect(hostname, port, username, password)
      require 'hawkular/hawkular_client'
      url         = URI::HTTP.build(:host => hostname, :port => port.to_i, :path => '/hawkular/alerts').to_s
      credentials = {
        :username => username,
        :password => password
      }
      ::Hawkular::Alerts::AlertsClient.new(url, credentials)
    end

    def alerts_connect
      self.class.raw_alerts_connect(hostname,
                                    port,
                                    authentication_userid('default'),
                                    authentication_password('default'))
    end

    # UI methods for determining availability of fields
    def supports_port?
      true
    end

    def self.ems_type
      @ems_type ||= "hawkular".freeze
    end

    def self.description
      @description ||= "Hawkular".freeze
    end

    def self.event_monitor_class
      ManageIQ::Providers::Hawkular::MiddlewareManager::EventCatcher
    end

    # To blacklist defined event types by default add them here...
    def self.default_blacklisted_event_names
      %w(
      )
    end

    def self.update_alert_profiles(*args)
      miq_alert_profile = {
        :id              => args[0][:profile_id],
        :old_alerts_ids  => args[0][:old_alerts],
        :new_alerts_ids  => args[0][:new_alerts]
      }
      if args[0][:operation] == :update_assignments
        old_assignments = args[0][:old_assignments]
        new_assignments = args[0][:new_assignments]
        old_ids = []
        new_ids = []
        unless old_assignments.empty?
          if old_assignments[0].class.name == "MiqEnterprise"
            MiddlewareManager.find_each { |m| m.middleware_servers.each { |eap| old_ids << eap.id } }
          else
            old_ids = old_assignments.collect { |eap| eap.id }
          end
        end
        unless new_assignments.nil? || new_assignments["assign_to"].nil?
          if new_assignments["assign_to"] == "enterprise"
            # Note that in this version the assign to enterprise is resolved at the moment of the assignment
            # In following iterations, enterprise assignment should be managed dynamically on the provider
            MiddlewareManager.find_each { |m| m.middleware_servers.each { |eap| new_ids << eap.id } }
          else
            new_ids = new_assignments["objects"]
          end
        end
        miq_alert_profile[:to_unassign_ids] = old_ids.select { |x| !new_ids.include?(x) }
        miq_alert_profile[:to_assign_ids] = new_ids.select { |x| !old_ids.include?(x) }
      end
      MiddlewareManager.find_each { |m| m.alert_profile_manager.process_alert_profile(args[0][:operation], miq_alert_profile) }
    end

    def self.update_alert(*args)
      miq_alert = {
        :id          => args[0][:alert][:id],
        :enabled     => args[0][:alert][:enabled],
        :description => args[0][:alert][:description],
        :conditions  => args[0][:alert][:expression]
      }
      MiddlewareManager.find_each { |m| m.alert_manager.process_alert(args[0][:operation], miq_alert) }
    end

    def alert_manager
      @alert_manager ||= ManageIQ::Providers::Hawkular::MiddlewareManager::AlertManager.new(self)
    end

    def alert_profile_manager
      @alert_profile_manager ||= ManageIQ::Providers::Hawkular::MiddlewareManager::AlertProfileManager.new(self)
    end

    private

    # Trigger running a (Hawkular) operation on the
    # selected target server. This server is identified
    # by ems_ref, which in Hawkular terms is the
    # fully qualified resource path from Hawkular inventory
    def run_generic_operation(operation, ems_ref)
      client = operations_connect

      the_operation = {
        :operationName => operation,
        :resourcePath  => ems_ref.to_s
      }

      actual_data = {}
      client.invoke_generic_operation(the_operation) do |on|
        on.success do |data|
          _log.debug "Success on websocket-operation #{data}"
          actual_data[:data] = data
        end
        on.failure do |error|
          actual_data[:data]  = {}
          actual_data[:error] = error
          _log.error 'error callback was called, reason: ' + error.to_s
        end
      end
    end
  end
end
