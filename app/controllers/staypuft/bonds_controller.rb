module Staypuft
  class BondsController < Staypuft::ApplicationController
    before_filter :find_hosts
    before_filter :find_bonds, :only => %w(destroy add_slave remove_slave change_mode)

    def create
      @bonds = []
      @hosts.each do |host|

        existing = host.interfaces.select { |i| i.is_a?(Nic::Bond) }.map(&:identifier)
        i = 0
        while existing.include?("bond#{i}") do
          i +=1
        end

        bond = Nic::Bond.new
        bond.identifier = "bond#{i}"
        params[:interfaces].each do |interface|
          bond.add_slave(interface)
        end
        bond.mode = 'balance-tlb'
        bond.bond_options = 'miimon=100'
        bond.host = host
        @bonds.push bond
      end

      ActiveRecord::Base.transaction do
        results = @bonds.map(&:save)
        @result = results.all?
        clear_nic_assignments(params[:interfaces])
        raise ActiveRecord::Rollback unless @result
      end

      find_unassigned_subnets
    end

    def destroy
      ActiveRecord::Base.transaction do
        clear_nic_assignments([params[:id]])
        results = @bonds.map(&:destroy)
        @result = results.all?
        raise ActiveRecord::Rollback unless @result
      end

      find_unassigned_subnets
    end

    def add_slave
      @bonds.each { |bond| bond.add_slave(params[:interface]) }

      ActiveRecord::Base.transaction do
        results = @bonds.map(&:save)
        @result = results.all?
        clear_nic_assignments([params[:interface]])
        raise ActiveRecord::Rollback unless @result
      end

      find_unassigned_subnets
    end

    def change_mode
      @bonds.each { |bond| bond.mode = params[:mode] }

      ActiveRecord::Base.transaction do
        results = @bonds.map(&:save)
        @result = results.all?
        raise ActiveRecord::Rollback unless @result
      end

      render :nothing => true
    end


    def remove_slave
      @bonds.each { |bond| bond.remove_slave(params[:interface]) }

      ActiveRecord::Base.transaction do
        results = @bonds.map(&:save)
        @result = results.all?
        clear_nic_assignments(params[:interfaces])
        raise ActiveRecord::Rollback unless @result
      end
    end

    private

    def find_bonds
      @bonds = @hosts.map do |host|
        host.interfaces.detect { |i| i.identifier == params[:id] }
      end
    end

    def find_hosts
      @hosts = Host::Managed.where(:id => params[:host_ids]).includes(:interfaces)
      @host = @hosts.first
      @interfaces = @host.interfaces.where("type <> 'Nic::BMC'").non_vip.order(:identifier).where(['(virtual = ? OR type = ?)', false, 'Nic::Bond'])
      @deployment = Deployment.find(params[:deployment_id])
    end

    def find_unassigned_subnets
      assigned_subnet_ids = ([@host.subnet_id] + @host.interfaces.non_vip.map(&:subnet_id)).compact.uniq
      @subnets = @deployment.subnets.where(["#{Subnet.table_name}.id NOT IN (?)", assigned_subnet_ids]).uniq
    end

    def clear_nic_assignments(interface_identifiers)
      @hosts.each do |host|
        interface_identifiers.each do |interface_identifier|

          if host.primary_interface == interface_identifier
            interface = host
          else
            interface = host.interfaces.find_by_identifier(interface_identifier)
          end

          subnet_typing = Staypuft::SubnetTyping.includes('subnet_type').where(:deployment_id => @deployment, :subnet_id => interface.subnet).first
          if subnet_typing
            next if subnet_typing.subnet_type.name == Staypuft::SubnetType::PXE

            assigner = InterfaceAssigner.new(@deployment, interface, interface.subnet)
            assigner.unassign
          end
        end
      end
    end
  end
end
