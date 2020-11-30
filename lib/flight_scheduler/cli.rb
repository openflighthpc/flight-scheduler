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

require 'commander'

require_relative 'config'
require_relative 'version'
require_relative 'auth'
require_relative 'commands'

module FlightScheduler
  class CLI
    extend Commander::CLI

    def self.create_command(name, args_str = '')
      command(name) do |c|
        c.syntax = "#{program :name} #{name} #{args_str}"
        c.hidden if name.split.length > 1

        c.action do |args, opts|
          Commands.build(name, *args, **opts.to_h).run!
        end

        yield c if block_given?
      end
    end

    # Configures the CLI from the config
    regex = /(?<=\Aprogram_).*\Z/
    Config.properties.each do |prop|
      if match = regex.match(prop.to_s)
        sym = match[0].to_sym
        program sym, Config::CACHE[prop]
      end
    end

    # Forces version to match the code base
    program :version, "v#{FlightScheduler::VERSION}"
    program :help_paging, false

    if [/^xterm/, /rxvt/, /256color/].all? { |regex| ENV['TERM'] !~ regex }
      Paint.mode = 0
    end

    create_command 'info' do |c|
      c.summary = 'List the available partitions and nodes'
      c.slop.string '-O', '--Format', <<~DESC.chomp
        Specify the format the information wil be displayed in. Must be comma separeted list of the following options:

        #{Commands::Info::Lister::OTHER_FIELDS.map { |k, v| "* #{k}: #{v}" }.join("\n")}

        The following field will list each partition individually:
        #{Commands::Info::Lister::PARTITION_FIELDS.map { |k, v| "* #{k}: #{v}" }.join("\n")}

        The following field will list each node individually:
        #{Commands::Info::Lister::NODE_FIELDS.map { |k, v| "* #{k}: #{v}" }.join("\n")}
      DESC
      c.slop.string '-o', '--format', <<~DESC.chomp
        Specify the format the information wil be displayed in:

        #{Commands::Info::Lister::OTHER_TYPES.map { |k, v| "* %#{k}: #{v}" }.join("\n")}

        The following field will list each partition individually:
        #{Commands::Info::Lister::PARTITION_TYPES.map { |k, v| "* %#{k}: #{v}" }.join("\n")}

        The following field will list each node individually:
        #{Commands::Info::Lister::NODE_TYPES.map { |k, v| "* %#{k}: #{v}" }.join("\n")}
      DESC
    end

    MAGIC_BATCH_SLOP = Slop::Options.new.tap do |slop|
      slop.parser.config[:suppress_errors] = true
      slop.string '-N', '--nodes', 'The minimum number of required nodes'
      slop.string '-a', '--array', <<~EOF
        Submit a job array, multiple jobs to be  executed  with  identical
        parameters.  The indexes  specification  identifies  what  array index
        values should be used. Multiple values may be specified using a comma
        separated list, e.g., --array=1,2,3,4.
      EOF
      slop.string '-o', '--output', 'Redirect STDOUT to this path'
      slop.string '-e', '--error', 'Redirect STDERR to this path'
      slop.string '--export', <<~EOF
        Identify which environment variables from the submission environment
        are propagated to the launched application.

        --export=ALL
        
          Default mode if --export is not specified. All of the users
          environment will be loaded from callers environment.
          
        --export=NONE
        
          No variables from the user environment will be defined.
          
        --export=<[ALL,]environment variables>
          
          Exports explicitly defined variables. Multiple environment variable
          names should be comma separated. Environment variable names may be
          specified to propagate the current value (e.g. "--export=EDITOR") or
          specific values may be exported (e.g. "--export=EDITOR=/bin/emacs").
          If ALL is specified, then all user environment variables will be
          loaded and will take precedence over any explicitly given
          environment variables.
      EOF
    end

    create_command 'batch', 'SCRIPT [ARGS...]' do |c|
      c.summary = 'Schedule a new job to be ran'
      MAGIC_BATCH_SLOP.each { |opt| c.slop.send(:add_option, opt.dup) }
      c.slop.string '-C', '--comment-prefix',
                    'Parse comment lines starting with COMMENT_PREFIX as additional options',
                    default: Config::CACHE.comment_prefix
    end

    create_command 'cancel', 'JOBID' do |c|
      c.summary = 'Remove a scheduled job'
    end

    create_command 'queue' do |c|
      c.summary = 'List all current jobs'
    end

    create_command 'alloc', '[COMMAND] [ARGS...]' do |c|
      c.summary = 'Obtain a resource allocation, execute the given command and release the allocation when the command is finished.'
      c.slop.string '-N', '--nodes',
                    'The minimum number of required nodes',
                    default: 1
    end

    create_command 'run', 'EXECUTABLE [ARGS...]' do |c|
      c.summary = 'Run EXECUTABLE under an already allocated job'
      c.slop.string '--jobid',
                    'Run under an already allocated job'
      c.slop.bool '--pty',
                    'Execute task zero in pseudo terminal mode.'
    end

    if Config::CACHE.development?
      create_command 'console' do |c|
        require_relative 'commands'
        c.action { FlightScheduler::Command.new().instance_exec { binding.pry } }
      end
    end
  end
end
