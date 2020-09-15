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

require 'json_api_client'

module FlightScheduler
  class BaseError < StandardError; end
  class InvalidInput < BaseError; end
  class UnexpectedError < BaseError
    MSG = 'An unexpected error has occurred!'

    def initialize(msg = MSG)
      super
    end
  end
  class ClientError < BaseError; end
  class InternalServerError < BaseError; end
  class ConnectionError < BaseError
    def initialize(msg = nil)
      super('Unable to connect to Flight Scheduler API')
    end
  end

  # A replacement for JsonApiClient::Errors::NotFound that doesn't throw away
  # the response.  This allows the error message to be inspected to determine
  # what was not found: the resource at the URL or one of its related
  # resources.
  class NotFound < JsonApiClient::Errors::ApiError
    attr_reader :uri

    def initialize(env)
      @uri = env[:url]
      super env
    end

    private

    # Try to fetch json_api errors from response
    #
    # A replacement for JsonApiClient::Errors::ApiError#track_json_api_errors
    # that prefers the error `detail` over the error `title`.
    def track_json_api_errors(msg)
      return msg unless env.try(:body).kind_of?(Hash) || env.body.key?('errors')

      errors = JsonApiClient::ErrorCollector.new(env.body.fetch('errors', []))
      errors_msg = errors
        .map { |e| e.error_msg(prefer_details: true) }
        .compact
        .join('; ')
        .presence

      return msg unless errors_msg

      msg.nil? ? errors_msg : "#{msg} (#{errors_msg})"
      # Just to be sure that it is back compatible
    rescue StandardError
      msg
    end
  end
end
