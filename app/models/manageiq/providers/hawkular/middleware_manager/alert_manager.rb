module ManageIQ::Providers
  class Hawkular::MiddlewareManager::AlertManager
    require 'hawkular/hawkular_client'

    def initialize(ems)
      @alerts_client = ems.alerts_connect
    end

    def process_alert(operation, miq_alert)
      new_group_trigger = convert_group_trigger(miq_alert)
      new_group_conditions = convert_group_conditions(miq_alert)
      case operation
      when :new
        @alerts_client.create_group_trigger(new_group_trigger)
        @alerts_client.set_group_conditions(new_group_trigger.id,
                                            :FIRING,
                                            new_group_conditions)
      when :update
        existing_group_trigger = @alerts_client.get_single_trigger(new_group_trigger.id, false)
        puts "DELETEME evaluate changes"
        p existing_group_trigger
        @alerts_client.update_group_trigger(new_group_trigger)
        @alerts_client.set_group_conditions(new_group_trigger.id,
                                            :FIRING,
                                            new_group_conditions)
      when :delete
        @alerts_client.delete_group_trigger(new_group_trigger.id)
      end
    end

    #  {'miq.event_type' => 'a_supported_event_type'}
    #  {'miq.event_type' => 'hawkular_event'}
    #  {'miq.resource_type' => 'a defined mw type in miq'}
    #  {'resource_path' => 'canonicalPathOfTheMiddlewareServer'}
    def convert_group_trigger(miq_alert)
      ::Hawkular::Alerts::Trigger.new('id'          => "MiQ-#{miq_alert[:id]}",
                                      'name'        => miq_alert[:description],
                                      'description' => miq_alert[:description],
                                      'enabled'     => miq_alert[:enabled],
                                      'type'        => :GROUP,
                                      'eventType'   => :EVENT)
    end

    def convert_group_conditions(miq_alert)
      case miq_alert[:conditions][:eval_method]
      when "mw_accumulated_gc_duration"       then generate_mw_gc_conditions(miq_alert)
      when "mw_heap_used", "mw_non_heap_used" then generate_mw_jvm_conditions(miq_alert)
      end
    end

    def generate_mw_gc_conditions(miq_alert)
      c = ::Hawkular::Alerts::Trigger::Condition.new({})
      c.trigger_mode = :FIRING
      c.data_id = MiddlewareServer::METRICS_MIQ_HWK[miq_alert[:conditions][:eval_method]]
      c.type = :RATE
      c.operator = convert_operator(miq_alert[:conditions][:options][:mw_operator])
      c.threshold = miq_alert[:conditions][:options][:value_mw_gc].to_i
      ::Hawkular::Alerts::Trigger::GroupConditionsInfo.new([c])
    end

    def generate_mw_jvm_conditions(miq_alert)
      c = []
      (0..1).each do |i|
        c[i] = ::Hawkular::Alerts::Trigger::Condition.new({})
        c[i].trigger_mode = :FIRING
        c[i].data_id = MiddlewareServer::METRICS_MIQ_HWK[miq_alert[:conditions][:eval_method]]
        c[i].type = :COMPARE
        c[i].data2_id = MiddlewareServer::METRICS_MIQ_HWK["mw_heap_max"]
      end
      c[0].operator = :GT
      c[0].data2_multiplier = miq_alert[:conditions][:options][:value_mw_gt].to_f/100
      c[1].operator = :LT
      c[1].data2_multiplier = miq_alert[:conditions][:options][:value_mw_lt].to_f/100
      ::Hawkular::Alerts::Trigger::GroupConditionsInfo.new(c)
    end

    def convert_operator(op)
      case op
      when "<"       then :LT
      when "<=", "=" then :LTE
      when ">"       then :GT
      when ">="      then :GTE
      end
    end
  end
end