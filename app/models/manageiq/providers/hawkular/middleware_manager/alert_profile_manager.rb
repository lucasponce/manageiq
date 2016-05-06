module ManageIQ::Providers
  class Hawkular::MiddlewareManager::AlertProfileManager
    require 'hawkular/hawkular_client'

    def initialize(ems)
      @alerts_client = ems.alerts_connect
    end

    def process_alert_profile(operation, miq_alert_profile)
      case operation
        when :update_alerts
          puts "DELETEME Update alerts in profile #{miq_alert_profile[:id]}"
          p miq_alert_profile
        when :update_assignments
          profile_id = miq_alert_profile[:id]
          to_unassign_ids = miq_alert_profile[:to_unassign_ids]
          to_assign_ids = miq_alert_profile[:to_assign_ids]
          if !to_unassign_ids.empty? || !to_assign_ids.empty?
            miq_alert_profile[:old_alerts_ids].each do |alert_id|
              group_trigger = @alerts_client.get_single_trigger "MiQ-#{alert_id}", true
              unassign_members(group_trigger, profile_id, to_unassign_ids) unless to_unassign_ids.empty?
              assign_members(group_trigger, profile_id, to_assign_ids) unless to_assign_ids.empty?
            end
          end
      end
    end

    def unassign_members(group_trigger, profile_id, members_ids)
      puts "DELETEME unassign from alert #{group_trigger.id} profile #{profile_id} members:"
      p members_ids
      context = group_trigger.context.nil? ? {} : group_trigger.context
      profiles = context['miq.alert_profiles'].nil? ? [] : context['miq.alert_profiles'].split(",")
      profiles -= [profile_id.to_s]
      context['miq.alert_profiles'] = profiles.uniq.join(",")
      group_trigger.context = context
      @alerts_client.update_group_trigger(group_trigger)
      if profiles.empty?
        members_ids.each do |member_id|
          @alerts_client.orphan_member("#{group_trigger.id}-#{member_id}")
          @alerts_client.delete_trigger("#{group_trigger.id}-#{member_id}")
        end
      end
    end

    def assign_members(group_trigger, profile_id, members_ids)
      context = group_trigger.context.nil? ? {} : group_trigger.context
      profiles = context['miq.alert_profiles'].nil? ? [] : context['miq.alert_profiles'].split(",")
      profiles.push(profile_id.to_s) unless profiles.include?(profile_id)
      context['miq.alert_profiles'] = profiles.uniq.join(",")
      group_trigger.context = context
      @alerts_client.update_group_trigger(group_trigger)
      members = @alerts_client.list_members group_trigger.id
      current_members_ids = members.collect { |m| m.id }
      members_ids.each do |member_id|
        unless current_members_ids.include?("#{group_trigger.id}-#{member_id}")
          server = MiddlewareServer.find(member_id)
          new_member = ::Hawkular::Alerts::Trigger::GroupMemberInfo.new
          new_member.group_id = group_trigger.id
          new_member.member_id = "#{group_trigger.id}-#{member_id}"
          new_member.member_name = "#{group_trigger.name} for #{server.name}"
          new_member.data_id_map = calculate_member_data_id_map(server, group_trigger)
          @alerts_client.create_member_trigger(new_member)
        end
      end
    end

    def calculate_member_data_id_map(server, group_trigger)
      data_id_map = {}
      group_trigger.conditions.each do |condition|
        data_id_map[condition.data_id] = "MI~R~[#{server.feed}/#{server.nativeid}]~MT~#{condition.data_id}"
        unless condition.data2_id.nil?
          data_id_map[condition.data2_id] = "MI~R~[#{server.feed}/#{server.nativeid}]~MT~#{condition.data2_id}"
        end
      end
      data_id_map
    end
  end
end