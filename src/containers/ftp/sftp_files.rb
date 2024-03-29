# frozen_string_literal: true

require "net/sftp"

load "./utils.rb"

# Class to act as SFTP client for uploading files to SFTP servers
class SftpFiles
  include Utils
  attr_reader :logger, :recorder

  def initialize(logger, recorder)
    @logger = logger || Logger.new($stdout)
    @recorder = recorder
  end

  def upload_file(uri, local_file, options = {})
    remote_host = CGI.unescape(uri.host) if uri.host
    remote_port = uri.port || 22
    remote_user = CGI.unescape(uri.user) if uri.user
    remote_password = CGI.unescape(uri.password) if uri.password
    remote_path = CGI.unescape(uri.path) if uri.path
    md5 = options[:md5].nil? ? false : options[:md5]

    logger.debug(JSON.dump({
      msg: "SFTP transfer setup",
      remote_host: remote_host,
      remote_port: remote_port,
      remote_user: remote_user,
      remote_path: remote_path,
      md5: md5
    }))

    Timeout.timeout(options[:timeout]) do
      Net::SFTP.start(
        remote_host,
        remote_user,
        password: remote_password,
        port: remote_port,
        non_interactive: true,
        timeout: options[:timeout],
        logger: logger
      ) do |sftp|
        # Given a URL like sftp://alice@example.com/foo/bar/baz.mp3, we have to
        # assume that /foo/bar is intended to be relative to the home directory
        #  of alice. `upload!` treats the `remote` argument as an absolute file
        # path, thus would try to upload to /foo/bar/baz.mp3 on the remote
        # system. We actually want something like /usr/alice/foo/bar/baz.mp3.
        # So we make the remote path relative to wherever the SFTP connection
        # starts in (by adding a leading period).
        sftp.upload!(local_file.path, ".#{remote_path}")

        if md5
          md5_file = create_md5_digest(local_file.path)
          sftp.upload!(md5_file.path, ".#{remote_path}.md5")
        end

        # send an EOF message for the channel before closing
        # https://github.com/net-ssh/net-ssh/issues/716
        sftp.channel.eof!
      end
    end
  end

  def create_md5_digest(file)
    digest = Digest::MD5.hexdigest(File.read(file))

    md5_digest_file = create_temp_file("#{file}.md5", false)
    md5_digest_file.write digest
    md5_digest_file.fsync
    md5_digest_file.close

    raise "Zero length md5 digest file: #{md5_digest_file.path}" if File.size(md5_digest_file.path).zero?

    md5_digest_file
  end
end
