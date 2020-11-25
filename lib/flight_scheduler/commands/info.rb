#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
#
# This file is part of Flight Scheduler.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# Flight Scheduler is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with Flight Scheduler. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on Flight Scheduler, please visit:
# https://github.com/openflighthpc/flight-scheduler
#===============================================================================

module FlightScheduler
  module Commands
    class Info < Command
      class Lister
        include OutputMode::TLDR::Index

        # Returns true if the output will contain state information, else false
        def state?
          @state ? true : false
        end

        # Returns true if the output will contain each hostname individually, else false
        def hostnames?
          @hostnames ? true : false
        end

        def register_default_columns
          register_partition
          register_column(header: 'AVAIL') { |_| 'TBD' }
          register_column(header: 'TIMELIMIT') { |_| 'TBD' }
          register_nodes
          register_state
          register_nodelist
        end

        def register_partition
          register_column(header: 'PARTITION') { |p| p.name }
        end

        def register_nodes
          register_column(header: 'NODES') { |p| p.nodes.length }
        end

        def register_state
          @state = true
          register_column(header: 'STATE') { |p| p.state }
        end

        def register_nodelist
          register_column(header: 'NODELIST') { |p| p.nodes.map(&:name).join(',') }
        end

        # NOTE: This method is used to quasi-list the nodes instead of partitions
        #
        # It assumes a one-to-one mapping of partitions to nodes. This is achieved using
        # the PartitionProxy and does not represent the underlining data model
        def register_hostnames
          @hostnames = true
          register_column(header: 'HOSTNAMES') { |p| p.nodes.first.name }
        end

        def register_cpus
          register_column(header: 'CPUS') do |p|
            value_or_min_plus(*p.nodes.map(&:cpus))
          end
        end

        def register_gpus
          register_column(header: 'GPUS') do |p|
            value_or_min_plus(*p.nodes.map(&:gpus))
          end
        end

        def register_memory
          register_column(header: 'MEMORY (MB)') do |p|
            value_or_min_plus(*p.nodes.map(&:gpus)) do |value|
              # Convert the memory into MB
              sprintf('%.2f', value.fdiv(1048576))
            end
          end
        end

        private

        def value_or_min_plus(*raws)
          # Ensures everything is an integer
          # NOTE: Also assumes nil should be interpreted as 0
          values = raws.map { |v| v.nil? ? 0 : v }

          # Determine the minimum and maximum value
          min = values.min
          max = values.max

          # Allows the caller to transform the value (used to handle floats)
          value = block_given? ? yield(min) : min

          # Append a plus if the maximum value is larger
          min == max ? value.to_s : "#{value}+"
        end
      end

      # Used to wrap the partition after it has been filtered either by
      # individual nodes or state
      class PartitionProxy < SimpleDelegator
        attr_reader :state, :nodes

        def initialize(partition, state: 'IDLE', nodes: nil)
          super(partition)
          @state = state
          @nodes = nodes || partition.nodes
        end
      end

      def lister
        @lister ||= if opts.format
          Lister.new.tap do |list|
            opts.format.split(',').each do |type|
              case type
              when 'NodeList'
                list.register_nodelist
              when 'NodeHost'
                list.register_hostnames
              when 'CPUs'
                list.register_cpus
              when 'GPUs'
                list.register_gpus
              when 'Memory'
                list.register_memory
              when 'State'
                list.register_state
              when 'Partition'
                list.register_partition
              end
            end
          end
        else
          Lister.new.tap(&:register_default_columns)
        end
      end

      def run
        records = PartitionsRecord.fetch_all(includes: ['nodes'], connection: connection)

        record_proxies = if lister.hostnames?
          # Create a one-to-one mapping between partitions and nodes
          # NOTE: This section will duplicate nodes which are in multiple partitions
          #       This may or may not be desirable depending if the 'Partitions' column
          #       is being displayed.
          #
          #       Consider revisiting once the desired behaviour is determined
          records.map do |partition|
            partition.nodes.map { |n| PartitionProxy.new(partition, state: n.state, nodes: [n]) }
          end.flatten.uniq { |p| [p.id, p.nodes.first.id] }

        elsif lister.state?
          # Group the nodes into partitions by state
          records.map do |record|
            # Collect the nodes by their state
            hash = Hash.new { |h, v| h[v] = [] }
            record.nodes.each { |node| hash[node.state] << node }

            # Create a proxy object for each partition-state combination
            if hash.empty?
              PartitionProxy.new(record)
            else
              hash.map do |state, nodes|
                PartitionProxy.new(record, state: state, nodes: nodes)
              end
            end
          end.flatten

        else
          # List the raw partitions
          records.map { |p| PartitionProxy.new(p) }
        end

        puts lister.build_output.render(*record_proxies)
      end
    end
  end
end
