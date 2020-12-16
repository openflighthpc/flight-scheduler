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

        # NOTE: Fix pluralisation in CLI once an additional type is added
        NODE_TYPES = {
          'n' => 'Hostname of the node',
        }
        # NOTE: Fix pluralisation in CLI once an additional type is added
        PARTITION_TYPES = {
          'R' => 'Partition name',
          'i' => 'Maximum time for a job'
          # TODO: Implement the concept of a "partition state"
          # This is different to the node state and can be up/down possible others
          # 'a' => 'State of the partition',
        }
        OTHER_TYPES = {
          'c' => 'Number of CPUs per node',
          'D' => 'Number of nodes',
          'm' => 'Memory per node (MB)',
          't' => 'State of the nodes'
        }
        FORMAT_REGEX = /\A%(?<size>\d*)(?<type>\w)\Z/

        # NOTE: Fix pluralisation in CLI once an additional field is added
        NODE_FIELDS = {
          'NodeHost' => 'The hostname of the node',
        }
        # NOTE: Fix pluralisation in CLI once an additional field is added
        PARTITION_FIELDS = {
          'Partition' => 'The name of the partition',
          'Time'      => 'Maximum time for a job'
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

          # These are required as some of the options may toggle a
          # 'nodes column' into a 'node column' or the 'state column'
          # into the 'state partition column'
          @node_basis = true      if fields.any? { |f| NODE_FIELDS.key?(f) }
          @partition_basis = true if fields.any? { |f| PARTITION_FIELDS.key?(f) }

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
              register_node_state
            when 'Partition'
              register_partition_name
            when 'Time'
              register_maximum_time
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

          # These are required as some of the options may toggle a
          # 'nodes column' into a 'node column' or the 'state column'
          # into the 'state partition column'
          @node_basis = true      if matches.any? { |m| NODE_TYPES.key?(m.named_captures['type']) }
          @partition_basis = true if matches.any? { |m| PARTITION_TYPES.key?(m.named_captures['type']) }

          matches.each do |match|
            type = match.named_captures['type']
            case type
            when 't'
              register_node_state
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
            when 'i'
              register_maximum_time
            else
              # NOTE: Ensure all of the above TYPES are implemented otherwise
              # this warning will be inconsistent
              warn_unrecognised_field(type)
            end
          end
        end

        # Returns true if the output will contain state information, else false
        def node_state?
          @node_state ? true : false
        end

        # Returns true if the output should list each node individually
        def node_basis?
          @node_basis ? true : false
        end

        def partition_basis?
          @partition_basis ? true : false
        end

        def register_default_columns
          register_partition_name
          # NOTE: This is the state of the partition, not the node's on the partition
          # The valid states *may* eventually be up, down, drain, inact (aka inactive).
          # It is assumed that all partitions are 'up'
          register_column(header: 'AVAIL') { |_| 'up' }
          register_maximum_time
          register_node_count
          register_node_state
          register_nodelist
        end

        private

        # ///////////////////////////////////////////////////////////
        # Main helper methods for selecting column type:
        # Each column can render: a partition, a node, or many nodes
        # A table can not contain both a partition and a node column
        # however the "nodes" can be shared
        def register_partition_column(**opts, &b)
          @partition_basis = true
          register_column(**opts) do |partition, _n|
            b.call(partition)
          end
        end

        def register_node_column(**opts, &b)
          @node_basis = true
          register_column(**opts) do |partition, nodes|
            b.call(nodes.first)
          end
        end

        def register_nodes_column(**opts, &b)
          register_column(**opts) do |partition, nodes|
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

        # Assumes all the nodes have been grouped by state
        # NOTE: Must be able to handle partitions without nodes
        def register_node_state
          @node_state = true
          register_nodes_column(header: 'STATE') do |nodes|
            nodes.first&.state
          end
        end

        def register_nodelist
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
          register_nodes_column(header: 'GPUS') do |nodes|
            value_or_min_plus(*nodes.map(&:gpus), default: 0)
          end
        end

        def register_memory
          register_nodes_column(header: 'MEMORY (MB)') do |nodes|
            value_or_min_plus(*nodes.map(&:memory), default: 1048576) do |value|
              # Convert the memory into MB
              sprintf('%d', value.fdiv(1048576))
            end
          end
        end

        def register_maximum_time
          register_partition_column(header: 'TIMELIMIT') do |partition|
            Command.convert_time(partition.attributes[:'max-time-limit'])
          end
        end

        def value_or_min_plus(*raws, default: 1)
          # Ensures everything is an integer
          # Ignores nil values
          values = raws.map { |v| v.nil? ? default : v }

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

        if records.empty?
          $stderr.puts '(none)'
          return
        end

        entries = if lister.node_basis? && lister.partition_basis?
          # List the data as if partition-node exist in a one-one relationship
          records.each_with_object([]) do |partition, memo|
            partition.nodes.each do |node|
              memo << [partition, [node]]
            end
          end

        elsif lister.node_basis?
          # List the data as if partition-node exist in many-one relationship
          # TODO: Consider replacing with a nodes query
          nodes = records.map(&:nodes).flatten.uniq { |n| n.name }
          if nodes.empty?
            $stderr.puts '(none)'
            return
          end
          nodes.map do |node|
            [nil, [node]]
          end

        elsif lister.node_state?
          # List the data as if partition-"node-state" is many-one
          # Defaults to partition-node in one-many
          records.each_with_object([]) do |partition, memo|
            # Collect the nodes by their state
            hash = Hash.new { |h, v| h[v] = [] }
            if partition.nodes.empty?
              hash['MISSING'] = []
            else
              partition.nodes.each { |node| hash[node.state] << node }
            end

            # Create a proxy object for each partition-state combination
            hash.map do |_, nodes|
              memo << [partition, nodes]
            end
          end

        else
          # Defaults to partition-node in one-many
          records.map { |p| [p, p.nodes] }
        end

        puts lister.build_output.render(*entries)
      end
    end
  end
end
