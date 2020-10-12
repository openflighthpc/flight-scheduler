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
require 'active_support/core_ext/string/inflections'
require 'timeout'
require 'open3'

module FlightScheduler
  module Auth
    class AuthenticationError < RuntimeError; end

    def self.call(name)
      const_string = name.classify
      auth_type = const_get(const_string)
    rescue NameError
      Config::CACHE.logger.fatal "Auth type not found: #{self}::#{const_string}"
      raise InternalError.define_class(128), 'Auth Type Not Found!'
    else
      auth_type.call
    end

    module Basic
      def self.call
        return Etc.getpwuid(Process.uid).name, ''
      end
    end

    module Munge
      def self.call
        token = Timeout.timeout(2) { Open3.capture2('munge -n') }
        if token.nil?
          raise Error.define_class(22), "Unable to obtain munge token"
        end
        token
      rescue Timeout::Error
        raise Error.define_class(22), "Unable to obtain munge token"
      end
    end
  end
end
