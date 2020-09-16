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
    class Batch < Command
      NUM_REGEX = /\A\d+[km]?\Z/

      def run
        ensure_shebang
        job = JobsRecord.create(arguments: args,
                                script: script_path,
                                min_nodes: min_nodes,
                                connection: connection)
        puts "Submitted batch job #{job.id}"
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
        regex = /\A##{opts.comment_prefix}\s(?<args>.*)$/
        File.read(script_path)
            .each_line
            .map { |l| regex.match(l) }
            .reject(&:nil?)
            .map { |m| m.named_captures['args'] }
            .join(' ')
      end

      def script_path
        @script_path ||= begin
          path = args.first
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
      end
    end
  end
end
