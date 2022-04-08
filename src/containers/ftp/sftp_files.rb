require 'net/sftp'

load './utils.rb'

class SftpFiles
  include Utils
  attr_reader :logger, :recorder

  def initialize(logger, recorder)
    @logger = logger || Logger.new($stdout)
    @recorder = recorder
  end

  def upload_file(uri, local_file, _options = {})
    remote_host = CGI.unescape(uri.host) if uri.host
    remote_path = CGI.unescape(uri.path) if uri.path
    remote_user = CGI.unescape(uri.user) if uri.user
    remote_password = CGI.unescape(uri.password) if uri.password

    Net::SFTP.start(remote_host, remote_user, password: remote_password) do |sftp|
      sftp.upload!(local_file.path, remote_path)

      if md5
        md5_file = create_md5_digest(local_file.path)
        sftp.upload!(local_file.path, "#{remote_path}.md5")
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
