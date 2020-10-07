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
  # A connection to the input/output of a single job step.
  #
  # Data written to `@write_pipe` is streamed through the connection to the
  # job step.
  #
  # Data read from the connection is streamed to `STDOUT`.
  class StepdConnection
    attr_reader :write_pipe

    def initialize(execution)
      @execution = execution
      @read_pipe, @write_pipe = IO.pipe
    end

    def close
      @write_pipe.close_write
    end

    def join
      @thread.join
    end

    def connect_to_command
      report_on_exception = Config::CACHE.log_level == 'debug'
      @thread = Thread.new do
        Thread.current.report_on_exception = report_on_exception
        connection = TCPSocket.new(@execution.node, @execution.port)

        input_thread = Thread.new do
          Thread.current.report_on_exception = report_on_exception
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
          Thread.current.report_on_exception = report_on_exception
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
end
