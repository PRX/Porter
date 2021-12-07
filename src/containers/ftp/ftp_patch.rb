# frozen_string_literal: true

require 'ipaddr'
require 'net/ftp'

# N.B. look at Socket AddrInfo stdlib, might be a better way to do this
class IPAddr
  IP4_PRIVATE_RANGES = [
    IPAddr.new('10.0.0.0/8'),
    IPAddr.new('172.16.0.0/12'),
    IPAddr.new('192.168.0.0/16'),
    IPAddr.new('127.0.0.0/8')
  ].freeze

  IP6_PRIVATE_RANGES = [IPAddr.new('fc00::/7'), IPAddr.new('::1')].freeze

  def private?
    ranges = ipv6? ? IP6_PRIVATE_RANGES : IP4_PRIVATE_RANGES
    ranges.each { |ipr| return true if ipr.include?(self) }
    false
  end

  def public?
    !private?
  end
end

module Net
  # Override the Net::FTP class to add overrides
  class FTP
    attr_accessor :remote_host

    # set to override host when ftp server returns a private/loopback IP on PASV
    attr_accessor :override_local

    # this makes active mode work by setting the public ip of the client
    attr_accessor :local_host

    def makepasv_with_override
      host, port = makepasv_without_override
      if remote_host
        host = remote_host
      elsif override_local && IPAddr.new(host).private?
        # server sent a bad/private IP, use the remote IP from the connection
        host = @sock.remote_address.ip_address
      end

      [host, port]
    end

    # rubocop:disable Style/Alias
    alias_method :makepasv_without_override, :makepasv
    alias_method :makepasv, :makepasv_with_override

    def makeport_with_override
      sock = TCPServer.open(@sock.addr[3], 0)
      port = sock.addr[1]
      # set the public ip for the client to receive connections to
      host = local_host || sock.addr[3]

      sendport(host, port)

      sock
    end

    alias_method :makeport_without_override, :makeport
    alias_method :makeport, :makeport_with_override
    # rubocop:enable Style/Alias
  end
end
