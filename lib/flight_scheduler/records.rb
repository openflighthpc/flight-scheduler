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

module FlightScheduler
  class BaseRecord < SimpleJSONAPIClient::Base
    def self.inherited(base)
      base.const_set('TYPE', base.name.split('::').last.sub(/Record\Z/, '').downcase)
      base.const_set('COLLECTION_URL', "/#{Config::CACHE.api_prefix}/#{base::TYPE}")
      base.const_set('INDIVIDUAL_URL', "#{base::COLLECTION_URL}/%{id}")
    end
  end

  class PartitionsRecord < BaseRecord
    attributes :name, :nodes

    has_many :nodes, class_name: 'FlightScheduler::NodesRecord'
  end

  class NodesRecord < BaseRecord
    attributes :name, :state
  end

  class JobsRecord < BaseRecord
    attributes :min_nodes, :script, :arguments, :state, :reason

    has_one :partition, class_name: 'FlightScheduler::PartitionsRecord'
    has_many :'allocated-nodes', class_name: 'FlightScheduler::NodesRecord'
  end
end

