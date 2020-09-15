# frozen_string_literal: true

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

module FlightScheduler
  class CLI
    extend Commander::CLI

    def self.create_command(name, args_str = '')
      command(name) do |c|
        c.syntax = "#{program :name} #{name} #{args_str}"
        c.hidden if name.split.length > 1

        c.action do |args, opts|
          require_relative 'commands'
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
      c.summary = 'List the available partitions'
    end

    create_command 'batch', 'SCRIPT [ARGS...]' do |c|
      c.summary = 'Schedule a new job to be ran'
      c.slop.integer '-N', '--nodes', 'The minimum number of required nodes'
    end

    if Config::CACHE.development?
      create_command 'console' do |c|
        require_relative 'commands'
        c.action { FlightScheduler::Command.new().instance_exec { binding.pry } }
      end
    end
  end
end
