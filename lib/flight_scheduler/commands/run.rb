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
require 'io/console'
require_relative '../stepd_connection'
require 'tty-screen'

module FlightScheduler
  module Commands
    class Run < Command
      def run
        create_con = connection.dup
        create_con.params = { include: 'executions' }
        job_step = JobStepsRecord.create(
          arguments: args[1..-1],
          job_id: job_id,
          path: resolve_path(args.first),
          pty: pty?,
          connection: create_con,
          environment: {
            'TERM' => ENV['TERM'],
            'COLUMNS' => TTY::Screen.columns,
            'LINES' => TTY::Screen.lines
          },
        )

        # Long poll until the job step has been submitted to all nodes
        # NOTE: Sometimes the submission is sufficiently fast that this
        #       wait is skipped completely
        con = connection.dup
        con.params = { long_poll_submitted: true }
        until job_step.submitted
          job_step = JobStepsRecord.fetch(
            includes: ['executions'],
            connection: con,
            url_opts: { id: "#{job_id}.#{job_step.id}" },
          )
        end

        if pty? && job_step.executions.length > 1
          # If we're running a PTY session, we expect to have only a single
          # execution running.  Whilst it might be possible to send STDIN to
          # all sessions and have STDOUT/STDERR come back from only the first,
          # we don't currently support this.
          raise "PTY session on multiple nodes is not supported."
        end
        connections = create_job_step_connections(job_step)
        input_thread = create_input_thread(connections)
        connections.each(&:join)
        input_thread.kill if input_thread.alive?
      ensure
        connections.each(&:close) if connections
      end

      private

      def job_id
        job_id_env_var = "#{Config::CACHE.env_var_prefix}JOB_ID"
        if opts.jobid
          opts.jobid
        elsif ENV[job_id_env_var]
          ENV[job_id_env_var]
        else
          raise InputError, <<~ERROR.chomp
            --jobid must be given
          ERROR
        end
      end

      def pty?
        !!opts.pty
      end

      def create_job_step_connections(job_step)
        job_step.executions.map do |execution|
          StepdConnection.new(execution).tap do |conn|
            conn.connect_to_command
          end
        end
      end

      def create_input_thread(connections)
        report_on_exception = Config::CACHE.log_level == 'debug'
        if pty?
          # Currently we only support PTY sessions on a single node.
          write_pipe = connections.first.write_pipe
          Thread.new do
            Thread.current.report_on_exception = report_on_exception
            STDIN.raw do |stdin|
              IO.copy_stream(stdin, write_pipe)
            end
          end
        else
          Thread.new do
            Thread.current.report_on_exception = report_on_exception
            begin
              loop do
                if STDIN.eof? || STDIN.closed?
                  break
                end
                input = STDIN.gets
                connections.each do |conn|
                  conn.write_pipe.write(input)
                  conn.write_pipe.flush
                end
              end
            rescue IOError, Errno::EBADF, Errno::EPIPE, Errno::EIO
              # These exceptions are not unexpected.  We just want to
              # silence them.
            ensure
              connections.each(&:close)
            end
          end
        end
      end
    end
  end
end
