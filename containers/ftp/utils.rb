module Utils
  MAX_FILENAME_LENGTH ||= 160
  MAX_EXTENSION_LENGTH ||= 6
  def create_temp_file(base_file_name = nil, bin_mode = true)
    tmp_dir = './tmp'
    file_name = File.basename(base_file_name)
    if file_name.length > MAX_FILENAME_LENGTH
      file_name = Digest::SHA256.hexdigest(base_file_name)
    end
    file_ext = File.extname(base_file_name)[0, MAX_EXTENSION_LENGTH]

    FileUtils.mkdir_p(tmp_dir) unless File.exists?(tmp_dir)
    tmp = Tempfile.new([file_name, file_ext], tmp_dir)
    tmp.binmode if bin_mode
    tmp
  end
end
