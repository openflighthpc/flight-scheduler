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

require 'socket'
require 'io/wait'
require 'io/console'

module FlightScheduler
  module Commands
    class Connect < Command
      def run
        socket = TCPSocket.new('localhost', 6308)
        Config::CACHE.logger.info('Connected to interactive session')
        console = IO.console
        send_socket_output_to_console(socket, console)
        while input = console.gets
          Config::CACHE.logger.info("Processing input #{input.inspect}")
          socket.write(input)
          socket.flush
          send_socket_output_to_console(socket, console)
        end
      ensure
        socket.close if socket
      end

      private

      def send_socket_output_to_console(socket, console)
        sleep 0.5
        while socket.ready?
          output = socket.read(socket.nread)
          Config::CACHE.logger.info "=== output: #{(output).inspect rescue $!.message}"
          console.write(output.chomp)
          console.flush
          sleep 0.5
        end
      end
    end
  end
end
