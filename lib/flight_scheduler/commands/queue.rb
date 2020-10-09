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
    class Queue < Command
      extend OutputMode::TLDR::Index

      INCLUDES = ['partition', 'allocated-nodes']

      register_column(header: 'JOBID') { |r| r.id }
      register_column(header: 'PARTITION') do |r|
        r.job.partition.name
      end
      register_column(header: 'NAME') do |r|
        r.job.attributes[:'script-name']
      end
      register_column(header: 'USER') { |j| j.username }
      register_column(header: 'ST') { |j| j.state }
      register_column(header: 'TIME') { |_| 'TBD' }
      register_column(header: 'NODES') { |j| j.attributes[:'min-nodes'] }
      register_column(header: 'NODELIST(REASON)') do |record|
        nodes = record.relationships[:'allocated-nodes'].map(&:name).join(',')
        if record.reason && nodes.empty?
          "(#{record.reason})"
        elsif record.reason
          "#{nodes} (#{record.reason})"
        else
          nodes
        end
      end

      def run
        records = JobsRecord.fetch_all(includes: INCLUDES, connection: connection)
        puts self.class.build_output.render(*records)
      end
    end
  end
end
