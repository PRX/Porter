# frozen_string_literal: true

require "net/ftp"

module Net
  # Override the Net::FTP class to add overrides
  #  - based on this closed patch: https://github.com/ruby/ruby/pull/1561
  class FTP
    # this makes active mode work by setting the public ip and port of the client
    attr_accessor :public_host_ip, :public_port_num

    # override the listening port with public_port_num
    def makeport_with_override
      port = [public_port_num.to_i, 0].max
      host = @bare_sock.local_address.ip_address
      puts "Net::FTP Patch: makeport_with_override: #{host}:#{port}"
      Addrinfo.tcp(host, port).listen
    end

    # rubocop:disable Style/Alias
    alias_method :makeport_without_override, :makeport
    alias_method :makeport, :makeport_with_override
    # rubocop:enable Style/Alias

    # override the host and port with public_host_ip and public_port_num
    def sendport_with_override(host, port)
      override_host = public_host_ip || host
      override_port = [public_port_num.to_i, port.to_i].max
      puts "Net::FTP Patch: sendport_with_override: default: #{host}:#{port}, override: #{override_host}:#{override_port}"
      sendport_without_override(override_host, override_port)
    end

    # rubocop:disable Style/Alias
    alias_method :sendport_without_override, :sendport
    alias_method :sendport, :sendport_with_override
    # rubocop:enable Style/Alias
  end
end
