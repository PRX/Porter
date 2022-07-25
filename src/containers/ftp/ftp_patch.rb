# frozen_string_literal: true
require 'net/ftp'

module Net
  # Override the Net::FTP class to add overrides
  #  - based on this closed patch: https://github.com/ruby/ruby/pull/1561
  class FTP
    # this makes active mode work by setting the public ip of the client
    attr_accessor :public_host_ip

    # override with the public_host_ip
    def sendport_with_override(host, port)
      if public_host_ip
        host = public_host_ip
      end
      sendport_without_override(host, port)
    end

    # rubocop:disable Style/Alias
    alias_method :sendport_without_override, :sendport
    alias_method :sendport, :sendport_with_override
    # rubocop:enable Style/Alias
  end
end
