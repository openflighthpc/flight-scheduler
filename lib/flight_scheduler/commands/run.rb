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
    class Run < Command
      def run
        job = JobsRecord.create(
          connection: connection,
          interactive: true,
          min_nodes: 1,
          script_name: script_path,
        )
        puts "Submitted interactive job #{job.id}"
      end

      def script_path
        @script_path ||= begin
          path = args.first
          # Handle absolute paths and explicit relative paths
          if File.absolute_path?(path) || path[0] == '.'
            path = File.expand_path(path)
            File.exists?(path) ? path : raise(MissingError, "Could not locate: #{path}")
          # Handle implicit relative paths
          elsif File.exists?(p = File.expand_path(path))
            p
          # Preform a PATH lookup as a fallback
          else
            # Do not assume PATH is correct, only consider absolute paths to be valid
            roots = ENV.fetch('PATH', '').split(':').select do |root|
              File.absolute_path?(root.to_s)
            end

            # Search for the root directory path
            root = roots.find do |r|
              File.exists? File.join(r, path)
            end

            # Return the absolute path or error
            root ? File.join(root, path) : raise(MissingError, "Could not locate: #{path}")
          end
        end
      end
    end
  end
end
