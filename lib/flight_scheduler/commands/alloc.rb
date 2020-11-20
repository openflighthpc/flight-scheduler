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
    class Alloc < Command
      def run
        job = JobsRecord.create(
          min_nodes: opts.nodes,
          connection: connection,
        )

        # Long Poll until the job becomes available
        if job.runnable
          puts "Job #{job.id} queued and waiting for resources"
          long_poll_id = "#{job.id}/long-poll-runnable"
          while job.runnable
            job = JobsRecord.fetch(
              connection: connection, url_opts: { id: long_poll_id }
            )
          end
        end

        # Exit early if the job is not RUNNING
        unless job.state == 'RUNNING'
          raise GeneralError, <<~ERROR.chomp
            Can not continue with the allocation as the job is in the #{job.state} state
          ERROR
        end

        puts "Job #{job.id} allocated resources"
        run_command_and_wait(job)
        job.delete
        puts "Job #{job.id} resources deallocated"
      end

      def run_command_and_wait(job)
        command = args.first || 'bash'
        child_pid = Kernel.fork do
          opts = {
            unsetenv_others: false,
          }
          env = {
            'JOB_ID' => job.id,
          }
          Kernel.exec(env, command, *args[1..-1], **opts)
        end
        Process.wait(child_pid)
      end
    end
  end
end
