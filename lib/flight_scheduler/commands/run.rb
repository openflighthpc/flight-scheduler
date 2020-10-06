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
      class Connection
        def initialize(execution)
          @execution = execution
          @read_pipe, @write_pipe = IO.pipe
        end

        def write(data)
          @write_pipe.write(data)
        end

        def flush
          @write_pipe.flush
        end

        def close
          @write_pipe.close_write
        end

        def join
          @thread.join
        end

        def connect_to_command
          Thread.report_on_exception = true
          @thread = Thread.new do
            connection = TCPSocket.new(@execution.node, @execution.port)

            input_thread = Thread.new do
              begin
                IO.copy_stream(@read_pipe, connection)
              rescue IOError, Errno::EBADF, Errno::EPIPE, Errno::EIO
                # These exceptions are not unexpected.  We just want to
                # silence them.
              ensure
                connection.close_write
              end
            end
            output_thread = Thread.new do
              begin
                IO.copy_stream(connection, STDOUT)
              rescue IOError, Errno::EBADF, Errno::EPIPE, Errno::EIO
              ensure
                # If the connection is closed by the server, we'll end up here.
                # However, input_thread will remain blocked at the
                # `IO.copy_stream` call.  To exit cleanly we need to kill the
                # thread.
                input_thread.kill
              end
            end
            input_thread.join
            output_thread.join
          ensure
            connection.close if connection
          end
        end
      end

      def run
        job_step = JobStepsRecord.create(
          arguments: args[1..-1],
          job_id: job_id,
          path: resolve_path(args.first),
          connection: connection,
        )
        puts "Job step #{job_step.id} added"
        sleep 1

        job_step = JobStepsRecord.fetch(
          includes: ['executions'],
          connection: connection,
          url_opts: { id: "#{job_id}.#{job_step.id}" },
        )

        input_thread = nil

        puts "Job step running"
        connections = job_step.executions.map do |execution|
          Connection.new(execution).tap do |conn|
            conn.connect_to_command
          end
        end
        input_thread = Thread.new do
          begin
            loop do
              if STDIN.eof? || STDIN.closed?
                break
              end
              input = STDIN.gets
              connections.each do |conn|
                conn.write(input)
                conn.flush
              end
            end
          rescue IOError, Errno::EBADF, Errno::EPIPE, Errno::EIO
            # These exceptions are not unexpected.  We just want to
            # silence them.
          ensure
            connections.each(&:close)
          end
        end

        connections.each(&:join)
        input_thread.kill if input_thread && input_thread.alive?
      rescue Interrupt
        if Kernel.const_defined?(:Paint)
          $stderr.puts "\n#{Paint['WARNING', :underline, :yellow]}: Cancelled by user"
        else
          $stderr.puts "\nWARNING: Cancelled by user"
        end
        exit(130)

      ensure
        connections.each(&:close) if connections
      end

      def job_id
        if opts.jobid
          opts.jobid
        elsif ENV['JOB_ID']
          ENV['JOB_ID']
        else
          raise InputError, <<~ERROR.chomp
            --jobid must be given
          ERROR
        end
      end
    end
  end
end
