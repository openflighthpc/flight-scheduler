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

require 'simple_jsonapi_client'
require 'active_support/inflector'

module FlightScheduler
  class BaseRecord < SimpleJSONAPIClient::Base
    def self.inherited(base)
      base.const_set(
        'TYPE',
        base.name.split('::').last.sub(/Record\Z/, '').underscore.dasherize
      )
      base.const_set('COLLECTION_URL', "/#{Config::CACHE.api_prefix}/#{base::TYPE}")
      base.const_set('INDIVIDUAL_URL', "#{base::COLLECTION_URL}/%{id}")
      base.const_set('SINGULAR_TYPE', base::TYPE.singularize)
    end

    ##
    # Override the delete method to nicely handle missing records
    def delete
      super
    rescue SimpleJSONAPIClient::Errors::NotFoundError
      if $!.response['content-type'] == 'application/vnd.api+json'
        # Handle proper API errors
        raise MissingError, <<~ERROR.chomp
          Could not locate #{self.class::SINGULAR_TYPE}: "#{self.id}"
        ERROR
      else
        # Fallback to the top level error handler
        raise e
      end
    end
  end

  class PartitionsRecord < BaseRecord
    attributes :name, :nodes, :'max-time-limit', :'default-time-limit'

    has_many :nodes, class_name: 'FlightScheduler::NodesRecord'
  end

  class NodesRecord < BaseRecord
    attributes :name, :state, :cpus, :gpus, :memory
  end

  class JobsRecord < BaseRecord
    CREATE_ERROR_MAP = {
      "/data/attributes/array"      => '--array ARRAY     - does not give a valid range expression',
      "/data/attributes/min-nodes"  => '--nodes MIN_NODES - must be a number with an optional k or m suffix'
    }

    def self.create(**_)
      super
    rescue SimpleJSONAPIClient::Errors::UnprocessableEntityError
      Config::CACHE.logger.debug "(#{$!.class}) #{$!.full_message}"

      base_msg = "Failed to create the job as the following error#{'s' unless $!.errors.length == 1} has occured:"
      errors = $!.errors.map do |e|
        pointer = e['source']['pointer']
        self::CREATE_ERROR_MAP[pointer] || "An unknown error has occurred: #{pointer}"
      end
      full_message = <<~ERROR.chomp
        #{base_msg}
        #{errors.map { |e| " * #{e}" }.join("\n")}
      ERROR
      raise ClientError, full_message
    end

    attributes :arguments,
      :array,
      :environment,
      :min_nodes,
      :reason,
      :script,
      :script_name,
      :state,
      :stderr_path,
      :stdout_path,
      :username,
      :cpus_per_node,
      :gpus_per_node,
      :memory_per_node,
      :exclusive,
      :time_limit,
      :time_limit_spec

    has_one :partition, class_name: 'FlightScheduler::PartitionsRecord'
    has_one :'shared-environment', class_name: 'FlightScheduler::EnvironmentsRecord'
    has_many :'allocated-nodes', class_name: 'FlightScheduler::NodesRecord'
  end

  class JobStepsRecord < BaseRecord
    attributes :arguments,
      :environment,
      :job_id,
      :path,
      :pty,
      :submitted

    has_one :job, class_name: 'FlightScheduler::JobsRecord'
    has_many :executions, class_name: 'FlightScheduler::ExecutionsRecord'
  end

  class ExecutionsRecord < BaseRecord
    attributes :node,
      :port,
      :state
  end

  class EnvironmentsRecord < BaseRecord
    attributes :hash
  end
end
