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

        NODE_TYPES = {
          'n' => 'Hostname of the node',
          't' => 'State of the nodes'
        }
        # NOTE: Fix pluralisation in CLI once an additional type is added
        PARTITION_TYPES = {
          'R' => 'Partition name'
        }
        OTHER_TYPES = {
          'a' => 'State of the partition or nodes',
          'c' => 'Number of CPUs per node',
          'D' => 'Number of nodes',
          'm' => 'Memory per node (MB)'
        }
        FORMAT_REGEX = /\A%(?<size>\d*)(?<type>\w)\Z/

        # NOTE: Fix pluralisation in CLI once an additional field is added
        NODE_FIELDS = {
          'NodeHost' => 'The hostname of the node',
        }
        # NOTE: Fix pluralisation in CLI once an additional field is added
        PARTITION_FIELDS = {
          'Partition' => 'The name of the partition'
        }
        OTHER_FIELDS = {
          'NodeList' => 'All the nodes in the partition',
          'CPUs' => 'The number of cpus',
          'GPUs' => 'The number of gpus',
          'Memory' => 'The total amount of memory',
          'State' => 'The state of the partition or nodes',
        }

        def parse_field_format(format)
          fields = format.split(',')

          # Determine if any mutually exclusive types have been used
          nodes = fields.select { |f| NODE_FIELDS[f] }
          partitions = fields.select { |f| PARTITION_FIELDS[f] }

          unless nodes.empty? || partitions.empty?
            types = [*nodes, *partitions]
            raise InputError, <<~ERROR.chomp
              Can not use the following formats together as it requires listing both nodes and partitions:
              #{types.join(",")}
            ERROR
          end

          @node_basis = true unless nodes.empty?

          fields.each do |field|
            case field
            when 'NodeList'
              register_nodelist
            when 'NodeHost'
              register_hostnames
            when 'CPUs'
              register_cpus
            when 'GPUs'
              register_gpus
            when 'Memory'
              register_memory
            when 'State'
              register_state
            when 'Partition'
              register_partition_name
            else
              # NOTE: Ensure all of the above FIELDS are implemented otherwise
              # this warning will be inconsistent
              warn_unrecognised_field(field)
            end
          end
        end

        def parse_type_format(format)
          matches = format.split(/\s+/).map do |field|
            FORMAT_REGEX.match(field) || begin
              warn_unrecognised_field(field)
              nil
            end
          end.reject(&:nil?)

          # Determine if any mutually exclusive types have been used
          nodes = matches.select { |m| NODE_TYPES[m.named_captures['type']] }
          partitions = matches.select { |m| PARTITION_TYPES[m.named_captures['type']] }

          unless nodes.empty? || partitions.empty?
            types = [*nodes, *partitions].map(&:to_s)
            raise InputError, <<~ERROR.chomp
              Can not use the following formats together as it requires listing both nodes and partitions:
              #{types.join(" ")}
            ERROR
          end

          @node_basis = true unless nodes.empty?

          matches.each do |match|
            type = match.named_captures['type']
            case type
            when 'a'
              register_state
            when 'c'
              register_cpus
            when 'D'
              register_node_count
            when 'm'
              register_memory
            when 'n'
              register_hostnames
            when 'R'
              register_partition_name
            else
              # NOTE: Ensure all of the above TYPES are implemented otherwise
              # this warning will be inconsistent
              warn_unrecognised_field(type)
            end
          end
        end

        # Returns true if the output will contain state information, else false
        def state?
          @state ? true : false
        end

        # Returns true if the output should list each node individually
        def node_basis?
          @node_basis ? true : false
        end

        def register_default_columns
          register_partition_name
          register_column(header: 'AVAIL') { |_| 'TBD' }
          register_column(header: 'TIMELIMIT') { |_| 'TBD' }
          register_node_count
          register_state
          register_nodelist
        end

        private

        # ///////////////////////////////////////////////////////////
        # Main helper methods for selecting column type:
        # Each column can render: a partition, a node, or many nodes
        # A table can not contain both a partition and a node column
        # however the "nodes" can be shared
        def register_partition_column(**opts, &b)
          register_column(**opts) do |partition, _n, _s|
            raise InternalError, <<~ERROR.chomp if partition.nil?
              Attempted to render a partition within a node context
            ERROR
            b.call(partition)
          end
        end

        def register_node_column(**opts, &b)
          register_column(**opts) do |partition, nodes, _s|
            raise InternalError, <<~ERROR.chomp unless partition.nil?
              Attempted to render a node within a partition context
            ERROR
            raise InternalError, <<~ERROR.chomp unless node.length == 1
              Attempted to render a node with '#{node.length}' nodes
            ERROR
            b.call(nodes.first)
          end
        end

        def register_nodes_column(**opts, &b)
          register_column(**opts) do |partition, nodes, _s|
            nodes ||= (partition.nodes || [])
            b.call(nodes)
          end
        end
        # End main helpers
        # The following register an actual column
        # ///////////////////////////////////////////////////////////

        def register_partition_name
          register_partition_column(header: 'PARTITION') { |p| p.name }
        end

        def register_node_count
          register_nodes_column(header: 'NODES') { |n| n.length }
        end

        def register_state
          @state = true
          register_column(header: 'STATE') do |_p, _n, state|
            raise InternalError, <<~ERROR.chomp if state.nil?
              Attempted to renderer without a state
            ERROR
            state
          end
        end

        def register_nodes_nodelist
          register_nodes_column(header: 'NODELIST') { |n| n.map(&:name).join(',') }
        end

        # NOTE: This method is used to quasi-list the nodes instead of partitions
        #
        # It assumes a one-to-one mapping of partitions to nodes. This is achieved using
        # the PartitionProxy and does not represent the underlining data model
        def register_hostnames
          register_node_column(header: 'HOSTNAMES') { |n| n.name }
        end

        def register_cpus
          register_nodes_column(header: 'CPUS') do |nodes|
            value_or_min_plus(*nodes.map(&:cpus))
          end
        end

        def register_gpus
          register_nodes_column(header: 'GPUS') do |p|
            value_or_min_plus(*nodes.map(&:gpus))
          end
        end

        def register_memory
          register_nodes_column(header: 'MEMORY (MB)') do |p|
            value_or_min_plus(*nodes.map(&:gpus)) do |value|
              # Convert the memory into MB
              sprintf('%.2f', value.fdiv(1048576))
            end
          end
        end

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

        def warn_unrecognised_field(field)
          msg = "Skipping unrecognised format field: #{field}"
          Config::CACHE.logger.warn(msg)
          $stderr.puts Paint[msg, :red]
        end
      end

      def lister
        @lister ||= Lister.new.tap do |list|
          if opts.Format
            list.parse_field_format(opts.Format)
          elsif opts.format
            list.parse_type_format(opts.format)
          else
            list.register_default_columns
          end
        end
      end

      def run
        records = PartitionsRecord.fetch_all(includes: ['nodes'], connection: connection)

        entries = if lister.node_basis?
          # List each node individually
          # Can not be used with the partition columns
          records.each_with_object([]) do |partition, memo|
            partition.nodes.each do |node|
              memo << [nil, [node], node.state]
            end
          end.uniq { |_p, n, _s| n.first.name }

        elsif lister.state?
          # Group the nodes into partitions by state
          records.each_with_object([]) do |partition, memo|
            # Collect the nodes by their state
            hash = Hash.new { |h, v| h[v] = [] }
            partition.nodes.each { |node| hash[node.state] << node }

            # Create a proxy object for each partition-state combination
            if hash.empty?
              # XXX: What should be the state of an empty partition?
              memo << [partition, [], 'IDLE']
            else
              hash.map do |state, nodes|
                memo << [partition, nodes, state]
              end
            end
          end

        else
          # List the raw partitions
          records.map { |p| [p, p.nodes, nil] }
        end

        puts lister.build_output.render(*entries)
      end
    end
  end
end
