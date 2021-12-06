# frozen_string_literal: true

load './ftp_patch.rb'
load './utils.rb'

# Class to act as FTP client for uploading files to FTP servers
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
  # - retry: retries by default, so this is true by default
  # - retry_wait: defaults to 10 seconds
  # - retry_max: when there is retry, defaults to 6 tries
  # - md5: will write an md5 by default, defaults to false
  # - keep_alive: will attempt to keep connections alive by default, true
  # - mode: FTP/Active, FTP/Passive, or FTP/Auto
  # - binary: binary transfer, true by default
  # - timeout: how long to spend trying to transfer the file

  # rubocop:disable Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/PerceivedComplexity
  def upload_file(uri, local_file, options = {})
    remote_host = CGI.unescape(uri.host) if uri.host
    remote_port = uri.port
    remote_path = CGI.unescape(uri.path) if uri.path
    remote_file_name = File.basename(remote_path)
    remote_directory = File.dirname(remote_path)
    remote_user = CGI.unescape(uri.user) if uri.user
    remote_password = CGI.unescape(uri.password) if uri.password

    # for logging
    anon_uri = URI.parse(uri.to_s)
    anon_uri.password = "#{remote_password[0]}#{'*' * (remote_password.length - 1)}"
    cstr = anon_uri.to_s

    public_ip = options[:public_ip]

    md5 = options[:md5].nil? ? false : options[:md5]
    md5_file = create_md5_digest(local_file.path) if md5

    # this may be turned to 0 on error
    keep_alive = options[:keep_alive].nil? ? 10 : options[:keep_alive].to_i

    retry_ftp = options[:retry].nil? ? true : options[:retry]
    retry_max = retry_ftp ? (options[:retry_max] || 6) : 1
    retry_wait = retry_ftp ? (options[:retry_wait] || 10) : 0
    retry_count = 0
    result = false

    # Start with passive mode for both FTP/Passive and FTP/Auto
    passive = options[:mode] != 'FTP/Active'

    while !result && (retry_count < retry_max)
      ftp = Net::FTP.new

      begin
        # this makes active mode work by sending the public ip of the client
        ftp.local_host = public_ip if public_ip

        # this works around when a remote server doesn't send its public IP
        ftp.override_local = true

        ftp.passive = passive
        ftp.binary = options[:binary].nil? ? true : options[:binary]
        ftp.open_timeout = nil # default is nil
        ftp.read_timeout = 60 # default is 60

        begin
          Timeout.timeout(60) do
            ftp.connect(remote_host, remote_port)
            ftp.login(remote_user, remote_password) if uri.userinfo
          end
        rescue StandardError => e
          logger.error "FTP connect failed: #{cstr}: #{e.message}"
          raise e
        end

        # if there is a remote dir that is not "."
        if remote_directory && remote_directory != '.'
          begin
            Timeout.timeout(60) do
              begin
                ftp.mkdir(remote_directory)
              rescue StandardError => e
                logger.warn("FTP mkdir failed: #{cstr}: #{e.message}")
              end
              ftp.chdir(remote_directory)
            end
          rescue StandardError => e
            logger.error "FTP chdir failed: #{cstr}: #{e.message}"
            raise e
          end
        end

        # deliver the file, catch errors and log when they occur
        # give each file some time to get ftp'd
        begin
          Timeout.timeout(options[:timeout]) do
            logger.debug("FTP start #{local_file.path} -> #{remote_file_name}")

            last_noop = Time.now.to_i
            bytes_uploaded = 0
            ftp.put(local_file.path, remote_file_name) do |chunk|
              bytes_uploaded += chunk.size

              if keep_alive.positive? && ((last_noop + keep_alive) < Time.now.to_i)
                last_noop = Time.now.to_i

                # this is to act as a keep alive - wbur needed it for remix delivery
                begin
                  ftp.noop
                rescue StandardError => e
                  # if they don't support this, and throw an error just keep going.
                  logger.warn("FTP noop error, off and retry: #{e.message}")
                  retry_count = [(retry_count - 1), 0].max
                  keep_alive = 0
                  raise e
                end

                # logger.debug "ftp put to #{remote_host}, #{bytes_uploaded} of #{local_file_size} bytes, (#{bytes_uploaded * 100 / local_file_size}%)."
              end
            end

            logger.debug "FTP put #{local_file.path} as #{remote_file_name}"

            if md5
              ftp.puttextfile(md5_file.path, "#{remote_file_name}.md5")
              logger.debug("FTP put #{md5_file.path} as #{remote_file_name}.md5")
            end
          end
        rescue StandardError => ex
          logger.error "FTP failed from '#{local_file.path}' to '#{cstr}'\n#{e.message}\n\t" + e.backtrace[0, 3].join("\n\t")
          raise ex
        end

        # if we get here, then it all worked!
        result = true

        # this records success!
        recorder.record('FtpSuccess', 'Count', 1.0)
      rescue StandardError => e
        # this records retried fails - open, login, mkdir, or put
        recorder.record('FtpError', 'Count', 1.0)

        # this can happen when this should be an active, not passive mode
        # only try half the retry attempts in this case
        if options[:mode] == 'FTP/Auto' && ((retry_count + 1) >= ((retry_max || 0) / 2).to_i)
          passive = false
          retry_count = 0
          logger.error "FTP retry as active (#{retry_count}): #{e.message}"
        else
          logger.error "FTP retry (#{retry_count}): #{e.message}"
          retry_count += 1
        end
        sleep(retry_wait)
      ensure
        begin
          ftp.close if ftp && !ftp.closed?
        rescue Object => e
          logger.error "FTP failed on close: #{e.message}"
        end
      end
    end

    if result
      used_mode = passive ? 'FTP/Passive' : 'FTP/Active'
      logger.debug("Finished sending file using #{used_mode}")
      used_mode
    else
      # this records final fail (no more retries)
      recorder.record('FtpFail', 'Count', 1.0)
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
    logger.debug "File md5 digest = #{digest}"

    md5_digest_file = create_temp_file("#{file}.md5", false)
    md5_digest_file.write digest
    md5_digest_file.fsync
    md5_digest_file.close

    raise "Zero length md5 digest file: #{md5_digest_file.path}" if File.size(md5_digest_file.path).zero?

    md5_digest_file
  end
end
