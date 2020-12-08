load './ftp_patch.rb'
load './utils.rb'

class FtpFiles
  include Utils
  attr_reader :logger

  def initialize(logger)
    @logger = logger || Logger.new(STDOUT)
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
  # - md5: will write an md5 by default, defaults to true
  # - keep_alive: will attempt to keep connections alive by default, true
  # - passive: use passive mode, true by default
  # - binary: binary transfer, true by default
  def upload_file(uri, local_file, options = {})
    remote_host = URI.decode(uri.host) if uri.host
    remote_port = uri.port
    remote_path = URI.decode(uri.path)
    remote_file_name = File.basename(remote_path)
    remote_directory = File.dirname(remote_path)
    remote_user = URI.decode(uri.user) if uri.user
    remote_password = URI.decode(uri.password) if uri.password

    # for logging
    anon_uri = URI.parse(uri.to_s)
    anon_uri.password = "#{remote_password[0]}#{"*" * (remote_password.length - 1)}"
    cstr = anon_uri.to_s

    public_ip = options[:public_ip]

    md5 = options[:md5].nil? ? false : !!options[:md5]
    md5_file = create_md5_digest(local_file.path) if md5

    # this may be turned to active on error
    passive = options[:passive].nil? ? true : !!options[:passive]

    # this may be turned to 0 on error
    keep_alive = options[:keep_alive].to_i

    retry_ftp = options[:retry].nil? ? true : !!options[:retry]
    retry_max = retry_ftp ? (options[:retry_max] || 6) : 1
    retry_wait = retry_ftp ? (options[:retry_wait] || 10) : 0
    retry_count = 0

    result = false
    err = nil

    while (!result && (retry_count < retry_max))
      ftp = Net::FTP.new

      begin
        # this makes active mode work by sending the public ip
        ftp.local_host = public_ip if public_ip

        # this works around badly specified masquerade ip for pasv
        ftp.override_local = true

        ftp.passive = passive
        ftp.binary = options[:binary].nil? ? true : !!options[:binary]

        ftp.open_timeout = nil  # default is nil
        ftp.read_timeout = 60 # default is 60

        begin
          Timeout.timeout(60) do
            ftp.connect(remote_host, remote_port)
            ftp.login(remote_user, remote_password) if uri.userinfo
          end
        rescue StandardError => err
          logger.error "FTP connect failed: #{cstr}: #{err.message}"
          raise err
        end

        # if there is a remote dir that is not "."
        if remote_directory && remote_directory != '.'
          begin
            Timeout.timeout(60) do
              begin
                ftp.mkdir(remote_directory)
              rescue StandardError => err
                logger.warn("FTP mkdir failed: #{cstr}: #{err.message}")
              end
              ftp.chdir(remote_directory)
            end
          rescue StandardError => err
            logger.error "FTP chdir failed: #{cstr}: #{err.message}"
            raise err
          end
        end

        # deliver the file, catch errors and log when they occur
        # give each file 1/2 hour to get ftp'd
        begin
          Timeout.timeout(1800) do
            logger.debug("FTP start #{local_file.path} -> #{remote_file_name}")

            last_noop = Time.now.to_i

            # local_file_size = File.size(local_file)
            bytes_uploaded = 0

            ftp.put(local_file.path, remote_file_name) do |chunk|
              bytes_uploaded += chunk.size

              if (keep_alive > 0) && ((last_noop + keep_alive) < Time.now.to_i)
                last_noop = Time.now.to_i

                # this is to act as a keep alive - wbur needed it for remix delivery
                begin
                  ftp.noop
                rescue StandardError => err
                  # if they don't support this, and throw an error just keep going.
                  logger.warn("FTP noop error, off and retry: #{err.message}")
                  retry_count = [(retry_count - 1), 0].max
                  keep_alive = 0
                  raise err
                end

                # logger.debug "ftp put to #{remote_host}, #{bytes_uploaded} of #{local_file_size} bytes, (#{bytes_uploaded * 100 / local_file_size}%)."
              end
            end

            logger.debug "FTP put #{local_file.path} as #{remote_file_name}"

            if md5
              ftp.puttextfile(md5_file.path, remote_file_name + '.md5')
              logger.debug "FTP put #{md5_file.path} as #{remote_file_name}.md5"
            end
          end
        rescue StandardError => ex
          logger.error "FTP failed from '#{local_file.path}' to '#{cstr}'\n#{ex.message}\n\t" + ex.backtrace[0, 3].join("\n\t")
          raise ex
        end

        # if we get here, then it all worked!
        result = true

      rescue StandardError => err
        # this can happen when this should be an active, not passive mode
        # only try half the retry attempts in this case
        if passive && ((retry_count + 1) >= ((retry_max || 0) / 2).to_i)
          passive = false
          retry_count = 0
          logger.error "FTP retry as active (#{retry_count}): #{err.message}"
        else
          # need to do something to retry this - use new a13g func for this.
          logger.error "FTP retry (#{retry_count}): #{err.message}"
          retry_count += 1
          sleep(retry_wait)
        end
      ensure
        begin
          ftp.close if ftp && !ftp.closed?
        rescue Object => ex
          logger.error "FTP failed on close: #{ex.message}"
        end
      end
    end

    if !result
      if err
        raise err
      else
        raise "FTP failed, no more retries: from '#{local_file}' to '#{cstr}'"
      end
    end
  ensure
    md5_file.close rescue nil
    File.unlink(md5_file) rescue nil
  end

  def create_md5_digest(file)
    digest = Digest::MD5.hexdigest(File.read(file))
    logger.debug "File md5 digest = #{digest}"

    md5_digest_file = create_temp_file(file + '.md5', false)
    md5_digest_file.write digest
    md5_digest_file.fsync
    md5_digest_file.close

    if File.size(md5_digest_file.path) == 0
      raise "Zero length md5 digest file: #{md5_digest_file.path}"
    end
    md5_digest_file
  end
end
