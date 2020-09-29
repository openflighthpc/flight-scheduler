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
require 'json'
require 'async/http/endpoint'
require 'async/websocket/client'

module FlightScheduler
  module Commands
    class Connect < Command
      def run
        job = JobsRecord.fetch_all(
          includes: ['allocated-nodes'],
          connection: connection,
          # url_opts: { id: args[0] },
        ).detect { |j| j.id == args[0] }

        daemon_url = "http://127.0.0.1:6308/v0/"
        endpoint = Async::HTTP::Endpoint.parse(daemon_url)

        Async do |task|
          Async::WebSocket::Client.connect(endpoint) do |connection|
            # Async.logger.info("Connected to #{controller_url.inspect}")
            message = {
              arguments: job.arguments,
              command: 'RUN_INTERACTIVE_JOB',
              env: {},
              executable: job.attributes[:'script-name'],
              job_id: job.id,
            }
            connection.write(message)
            connection.flush
            # Config::CACHE.logger.info('Connected to interactive session')
            message = connection.read
# ::STDERR.puts "=== message: #{(message).inspect rescue $!.message}"
            if message[:command] == 'INTERACTIVE_JOB_STARTED'
              STDERR.puts('Connected to interactive session')
              console = IO.console

              Async do
# ::STDERR.puts "=== 1: #{(1).inspect rescue $!.message}"
                while message = connection.read
                  # ::STDERR.puts "=== message: #{(message).inspect rescue $!.message}"
                  if message[:command] == 'output'
                    console.write(message[:output])
                    console.flush
                  end
                end
                ::STDERR.puts "=== 1 ends"
              end

              Async do
# ::STDERR.puts "=== 2: #{(2).inspect rescue $!.message}"
                while input = console.gets
# ::STDERR.puts "=== input: #{(input).inspect rescue $!.message}"
                  connection.write({command: 'input', input: input})
                  connection.flush
                end
# ::STDERR.puts "=== 2 ends: #{(2).inspect rescue $!.message}"
              end

            else
              STDERR.puts('Failed to connect to interactive session')
            end
            # send_socket_output_to_console(connection, console)
            # while input = console.gets
            #   # Config::CACHE.logger.info("Processing input #{input.inspect}")
            #   connection.write({command: 'input', input: input})
            #   connection.flush
            #   send_socket_output_to_console(connection, console)
            # end
          end
        end
      rescue
        ::STDERR.puts "=== $!: #{($!).inspect rescue $!.message}"
      end

      private

      def send_socket_output_to_console(socket, console)
        sleep 0.5
        message = socket.read
        if message[:command] == 'output'
          console.write(message[:output])
          console.flush
        end
      end
    end
  end
end
