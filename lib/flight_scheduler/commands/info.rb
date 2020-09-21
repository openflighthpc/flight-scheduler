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
      extend OutputMode::TLDR::Index

      # Wraps the partition object after it's nodes have been filtered by a state
      class PartitionProxy < SimpleDelegator
        attr_reader :state, :nodes

        def initialize(partition, state: 'IDLE', nodes: [])
          @state = state
          @nodes = nodes
          super(partition)
        end
      end

      register_column(header: 'PARTITION') { |p| p.name }
      register_column(header: 'AVAIL') { |_| 'TBD' }
      register_column(header: 'TIMELIMIT') { |_| 'TBD' }
      register_column(header: 'NODES') { |p| p.nodes.length }
      register_column(header: 'STATE') { |p| p.state }
      register_column(header: 'NODELIST') { |p| p.nodes.map(&:name).join(',') }

      def run
        records = PartitionsRecord.fetch_all(includes: ['nodes'], connection: connection)
        record_proxies = records.map do |record|
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
        puts self.class.build_output.render(*record_proxies)
      end
    end
  end
end
