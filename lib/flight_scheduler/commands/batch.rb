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

require 'csv'

module FlightScheduler
  module Commands
    class Batch < Command
      NUM_REGEX = /\A\d+[km]?\Z/

      def run
        ensure_shebang
        job = JobsRecord.create(arguments: args[1..-1],
                                script_name: File.basename(script_path),
                                script: script_body,
                                array: merged_opts.array,
                                min_nodes: min_nodes,
                                stdout_path: merged_opts.output,
                                stderr_path: merged_opts.error,
                                environment: environment,
                                **shared_batch_alloc_opts,
                                connection: connection)
        # TODO: Remove the id array stripping, this is a bug in the API
        #       specification
        puts "Submitted batch job #{job.id.sub(/\[.*\Z/, '')}"
      end

      def environment
        Bundler.with_unbundled_env do
          # Default to displaying everthing
          return ENV.to_h unless merged_opts.export

          # Parse the string and remove the ALL and NONE component
          parts   = CSV.parse(merged_opts.export).first || []
          all     = (parts.delete('ALL') ? true : false)
          parts.delete('NONE')

          # Convert the components into a hash
          others  = parts.each_with_object({}) do |part, memo|
            key, value = part.split('=', 2)
            memo[key] = value || ENV.fetch(key, '')
          end

          # Allow all the existing env vars to be exported
          all ? others.merge(ENV.to_h) : others
        end
      end

      def ensure_shebang
        File.open(script_path) do |file|
          shebang = file.gets(2).to_s
          raise InputError, <<~ERROR.chomp unless shebang == '#!'
            This does not look like a batch script!
            The first line must start with #! followed by the interpreter path.
            For instance: #{Paint["#!/bin/bash", :yellow]}
          ERROR
        end
      end

      def min_nodes
        return 1 unless merged_opts.nodes
        if NUM_REGEX.match? merged_opts.nodes
          merged_opts.nodes
        else
          raise InputError, <<~ERROR.chomp
            Unrecognized number syntax: #{merged_opts.nodes}
            It should be a number with an optional k or m suffix.
          ERROR
        end
      end

      def merged_opts
        @merged_opts ||= begin
          magic = CLI::MAGIC_BATCH_SLOP.parse(read_magic_arguments_string.split(' '))
                                       .to_h
                                       .reject { |_, v| v.nil? }
                                       .map { |k, v| [k.to_s, v] }
                                       .to_h
          cli = opts.reject { |_, v| v.nil? }
                    .map { |k, v| [k.to_s, v] }
                    .to_h
          Hashie::Mash.new.merge(magic).merge(cli)
        end
      end

      def read_magic_arguments_string
        args = []
        magic_comment_marker = "##{opts.comment_prefix} "
        script_body.each_line do |line|
          if line.start_with?(magic_comment_marker)
            args << line.sub(magic_comment_marker, '').chomp
          end
        end
        args.join(' ')
      end

      def script_body
        @script_body ||= File.read script_path
      end

      def script_path
        @script_path ||= resolve_path(args.first)
      end
    end
  end
end
