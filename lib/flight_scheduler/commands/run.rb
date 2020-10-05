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

        puts "Job step running"
        job_step.executions.each do |execution|
          connect_to_session(execution.node, execution.port)
        end
      end

      def connect_to_session(hostname, port)
        begin
          Thread.report_on_exception = false
          connection = TCPSocket.new(hostname, port)

          input_thread = Thread.new do
            begin
              IO.copy_stream(STDIN, connection)
            rescue IOError, Errno::EBADF
            ensure
              connection.close_write
            end
          end
          output_thread = Thread.new do
            begin
              IO.copy_stream(connection, STDOUT)
            rescue IOError, Errno::EBADF
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

        rescue Interrupt
          if Kernel.const_defined?(:Paint)
            $stderr.puts "\n#{Paint['WARNING', :underline, :yellow]}: Cancelled by user"
          else
            $stderr.puts "\nWARNING: Cancelled by user"
          end
          exit(130)
        ensure
          connection.close if connection
        end
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
