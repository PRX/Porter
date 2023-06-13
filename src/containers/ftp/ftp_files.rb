# frozen_string_literal: true

load "./ftp_patch.rb"
load "./utils.rb"

# Class to act as FTP client for uploading files to FTP servers
# rubocop:disable Metrics/ClassLength
class FtpFiles
  include Utils
  attr_reader :logger, :recorder

  def initialize(logger, recorder)
    @logger = logger || Logger.new($stdout)
    @recorder = recorder
  end

  #
  # upload_file
  #
  #  == Parameters:
  # @param uri [URI] the uri for where to FTP the file to
  # @param local_file
  # @param options [Hash]
  # - retry_wait: defaults to 10 seconds
  # - max_attempts: the number of times to try the transfer
  # - md5: will write an md5 by default, defaults to false
  # - keep_alive: attempt to keep connections alive with a noop every  N seconds, 0 / off by default
  # - mode: FTP/Active, FTP/Passive, or FTP/Auto
  # - binary: binary transfer, true by default
  # - timeout: how long to spend trying to transfer the file

  # rubocop:disable Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/PerceivedComplexity
  def upload_file(uri, local_file, options = {})
    remote_host = CGI.unescape(uri.host) if uri.host
    remote_port = uri.port || 21
    remote_path = CGI.unescape(uri.path) if uri.path
    remote_file_name = File.basename(remote_path)
    remote_directory = File.dirname(remote_path)
    remote_user = CGI.unescape(uri.user) if uri.user
    remote_password = CGI.unescape(uri.password) if uri.password

    # for logging
    anon_uri = URI.parse(uri.to_s)
    anon_uri.password = "#{CGI.escape(remote_password[0])}#{"*" * (remote_password.length - 1)}"
    cstr = anon_uri.to_s

    public_ip = options[:public_ip]
    public_port = options[:public_port]

    md5 = options[:md5].nil? ? false : options[:md5]
    md5_file = create_md5_digest(local_file.path) if md5

    # this may be turned to 0 on error
    keep_alive = options[:keep_alive].nil? ? 0 : options[:keep_alive].to_i

    use_tls = options[:use_tls].nil? ? false : options[:use_tls]

    max_attempts = options[:max_attempts] || 1
    retry_wait = options[:retry_wait] || 10
    attempt = 1
    result = false

    # Always make at least two total attempts with Auto mode, one for each
    max_attempts = 2 if options[:mode] == "FTP/Auto" && max_attempts < 2

    logger.debug(JSON.dump({
      msg: "FTP transfer setup",
      task_mode: options[:mode],
      public_ip: public_ip,
      public_port: public_port,
      use_tls: use_tls,
      md5: md5,
      remote_host: remote_host,
      remote_port: remote_port,
      remote_directory: remote_directory,
      remote_file_name: remote_file_name,
      remote_user: remote_user
    }))

    # Start with passive mode for both FTP/Passive and FTP/Auto
    passive = options[:mode] != "FTP/Active"

    while !result && (attempt <= max_attempts)
      sleep(retry_wait) if attempt > 1

      # When using FTP/Auto, failover to active mode after exhausting half
      # of the max retries. When max attempts is odd, passive mode will be
      # attempted one more time than active mode
      passive = false if options[:mode] == "FTP/Auto" && (attempt > (max_attempts / 2).ceil)

      ftp = Net::FTP.new(nil, ssl: use_tls)

      begin
        # this makes active mode work by sending the public ip and port of the client
        ftp.public_host_ip = public_ip if public_ip
        ftp.public_port_num = public_port if public_port

        # use_pasv_ip is false now by default. Uses the same IP for the command as for data
        ftp.use_pasv_ip = false

        ftp.passive = passive
        ftp.binary = options[:binary].nil? ? true : options[:binary]
        ftp.open_timeout = nil # default is nil
        ftp.read_timeout = 60 # default is 60
        # ftp.ssl = use_tls if use_tls
        # ftp.debug_mode = true

        begin
          Timeout.timeout(60) do
            ftp.connect(remote_host, remote_port)
            ftp.login(remote_user, remote_password) if uri.userinfo
          end
        rescue => e
          logger.error(JSON.dump({
            msg: "FTP connect/login failed",
            error: e.message,
            remote_host: remote_host,
            remote_port: remote_port,
            remote_user: remote_user,
            passive: passive,
            attempt: attempt
          }))
          raise e
        end

        # if there is a remote dir that is not "."
        if remote_directory && remote_directory != "."
          begin
            Timeout.timeout(60) do
              begin
                ftp.mkdir(remote_directory)
              rescue => e
                # This might be okay if the dir already exist, which we'll
                # find out when we chdir
                logger.warn(JSON.dump({
                  msg: "FTP mkdir failed",
                  error: e.message,
                  remote_directory: remote_directory,
                  passive: passive,
                  attempt: attempt
                }))
              end

              logger.debug(JSON.dump({
                msg: "FTP chdir",
                remote_directory: remote_directory,
                passive: passive,
                attempt: attempt
              }))
              ftp.chdir(remote_directory)
            end
          rescue => e
            # Can't recover from this because we can't put the file where the
            # job wants it
            logger.error(JSON.dump({
              msg: "FTP chdir failed",
              error: e.message,
              remote_directory: remote_directory,
              passive: passive,
              attempt: attempt
            }))
            raise e
          end
        end

        # deliver the file, catch errors and log when they occur
        # give each file some time to get ftp'd
        begin
          Timeout.timeout(options[:timeout]) do
            logger.debug(JSON.dump({
              msg: "FTP put starting",
              local_file: local_file.path,
              remote_directory: remote_directory,
              remote_file_name: remote_file_name,
              passive: passive,
              attempt: attempt
            }))

            last_noop = Time.now.to_i
            bytes_uploaded = 0
            ftp.put(local_file.path, remote_file_name) do |chunk|
              bytes_uploaded += chunk.size

              if keep_alive.positive? && ((last_noop + keep_alive) < Time.now.to_i)
                last_noop = Time.now.to_i

                # this is to act as a keep alive - wbur needed it for remix delivery
                begin
                  ftp.noop
                rescue => e
                  # if they don't support this, and throw an error just keep going.
                  logger.warn("FTP noop error, off and retry: #{e.message}")
                  attempt = [(attempt - 1), 1].max
                  keep_alive = 0
                  raise e
                end

                # logger.debug "ftp put to #{remote_host}, #{bytes_uploaded} of #{local_file_size} bytes, (#{bytes_uploaded * 100 / local_file_size}%)."
              end
            end

            logger.debug(JSON.dump({
              msg: "FTP put complete",
              local_file: local_file.path,
              remote_directory: remote_directory,
              remote_file_name: remote_file_name,
              passive: passive,
              attempt: attempt
            }))

            if md5
              ftp.puttextfile(md5_file.path, "#{remote_file_name}.md5")
              logger.debug(JSON.dump({
                msg: "FTP MD5 put complete",
                local_file: md5_file.path,
                remote_directory: remote_directory,
                remote_file_name: remote_file_name,
                passive: passive,
                attempt: attempt
              }))
            end
          end
        rescue => e
          logger.error(JSON.dump({
            msg: "FTP put failed",
            error: e.message,
            reason: e.backtrace[0, 3].join("\n\t"),
            local_file: local_file.path,
            remote_directory: remote_directory,
            remote_file_name: remote_file_name,
            passive: passive,
            attempt: attempt
          }))

          raise e
        end

        # if we get here, then it all worked!
        result = true

        # this records success!
        recorder.record("FtpSuccess", "Count", 1.0)
      rescue => e
        # this records retried fails - open, login, mkdir, or put
        recorder.record("FtpError", "Count", 1.0)

        attempt += 1
      ensure
        begin
          ftp.close if ftp && !ftp.closed?
        rescue Object => e
          logger.warn(JSON.dump({
            msg: "FTP close failed",
            error: e.message,
            passive: passive,
            attempt: attempt
          }))
        end
      end
    end

    if result
      used_mode = passive ? "FTP/Passive" : "FTP/Active"

      logger.debug(JSON.dump({
        msg: "FTP transfer complete",
        used_mode: used_mode,
        passive: passive,
        attempt: attempt
      }))

      used_mode
    else
      # this records final fail (no more retries)
      recorder.record("FtpFail", "Count", 1.0)
      raise "FTP failed, no more retries: from '#{local_file}' to '#{cstr}'"
    end
  ensure
    delete_temp_file(md5_file)
  end
  # rubocop:enable Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/PerceivedComplexity

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
# rubocop:enable Metrics/ClassLength
