module Staypuft
  class BondsController < Staypuft::ApplicationController
    before_filter :find_hosts
    before_filter :find_bonds, :only => %w(destroy add_slave remove_slave)

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
        bond.add_slave(params[:interface])
        bond.mode = 'balance-tlb'
        bond.bond_options = 'miimon=100'
        bond.host = host
        @bonds.push bond
      end

      ActiveRecord::Base.transaction do
        results = @bonds.map(&:save)
        @result = results.all?
        raise ActiveRecord::Rollback unless @result
      end
    end

    def destroy
      ActiveRecord::Base.transaction do
        results = @bonds.map(&:destroy)
        @result = results.all?
        raise ActiveRecord::Rollback unless @result
      end
    end

    def add_slave
      @bonds.each { |bond| bond.add_slave(params[:interface]) }

      ActiveRecord::Base.transaction do
        results = @bonds.map(&:save)
        @result = results.all?
        raise ActiveRecord::Rollback unless @result
      end
    end

    def remove_slave
      @bonds.each { |bond| bond.remove_slave(params[:interface]) }

      ActiveRecord::Base.transaction do
        results = @bonds.map(&:save)
        @result = results.all?
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
    end
  end
end