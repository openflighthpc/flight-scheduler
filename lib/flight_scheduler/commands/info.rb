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

      register_column(header: 'PARTITION') { |p| p.name }
      register_column(header: 'AVAIL') { |_| 'TBD' }
      register_column(header: 'TIMELIMIT') { |_| 'TBD' }
      register_column(header: 'NODES') { |p| p.nodes.length }
      register_column(header: 'STATE') { |_| 'TBD' }
      register_column(header: 'NODELIST') { |p| p.nodes.join(',') }

      def run
        records = PartitionsRecord.fetch_all(connection: connection)
        puts self.class.build_output.render(*records)
      end
    end
  end
end