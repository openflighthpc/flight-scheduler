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

require_relative 'records'
require_relative 'errors'

require 'faraday'
require 'faraday_middleware'
require 'output_mode'
require 'etc'

module FlightScheduler
  class Command
    class Options < Hashie::Mash
      disable_warnings :partition
    end

    def self.convert_time(seconds)
      return nil unless seconds
      days    = seconds / (60 * 60 * 24)
      seconds = seconds % (60 * 60 * 24)

      hours   = seconds / (60 * 60)
      seconds = seconds % (60 * 60)

      minutes = seconds / 60
      seconds = seconds % 60

      "#{days}-#{hours}:#{minutes}:#{seconds}"
    end

    attr_accessor :args, :opts

    def initialize(*args, **opts)
      @args = args.freeze
      @opts = Options.new(opts)
    end

    def run!
      Config::CACHE.logger.info "Running: #{self.class}"
      run
      Config::CACHE.logger.info 'Exited: 0'
    rescue => e
      if e.respond_to? :exit_code
        Config::CACHE.logger.fatal "Exited: #{e.exit_code}"
      else
        Config::CACHE.logger.fatal 'Exited non-zero'
      end
      Config::CACHE.logger.debug e.backtrace.reverse.join("\n")
      Config::CACHE.logger.error "(#{e.class}) #{e.message}"

      case e
      when Faraday::ConnectionFailed
        raise GeneralError, 'Failed to establish a connection to the scheduler!'
      else
        raise e
      end
    end

    def run
      raise NotImplementedError
    end

    def headers
      {
        'Content-Type' => 'application/vnd.api+json',
        'Accept' => 'application/vnd.api+json'
      }
    end

    def connection
      @connection ||= Faraday.new(url: Config::CACHE.base_url, headers: headers) do |c|
        if Config::CACHE.auth_type == 'basic'
          c.basic_auth(*Auth.call(Config::CACHE.auth_type))
        else
          c.authorization :Bearer, Auth.call(Config::CACHE.auth_type)
        end
        c.use Faraday::Response::Logger, Config::CACHE.logger, { bodies: true } do |l|
          l.filter(/(Authorization:)(.*)/, '\1 [REDACTED]')
        end
        c.request :json
        c.response :json, :content_type => /\bjson$/
        c.adapter :net_http
      end
    end

    def resolve_path(path)
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

    def shared_batch_alloc_opts(options=opts)
      {}.tap do |hash|
        hash[:cpus_per_node] = options.mincpus if options.mincpus
        hash[:gpus_per_node] = options.gpus_per_node if options.gpus_per_node
        hash[:exclusive] = true if options.exclusive
        hash[:time_limit_spec] = options.time if options.time
        if options.mem
          int = (/\d+/.match(options.mem) || [])[0].to_i

          hash[:memory_per_node] = case options.mem
          when /\A\d+(MB?)?\Z/
            int * 1048576
          when /\A\d+KB?\Z/
            int * 1024
          when /\A\d+GB?\Z/
            int * 1073741824
          when /\A\d+TB?\Z/
            int * 1099511627776
          else
            raise InputError, "Unrecognised memory amount: #{options.mem}"
          end
        end
      end
    end
  end
end
