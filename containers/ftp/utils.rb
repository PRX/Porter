# frozen_string_literal: true

# Reusable utility methods
module Utils
  MAX_FILENAME ||= 160
  MAX_EXTENSION ||= 6
  def create_temp_file(base_file_name, bin_mode)
    tmp_dir = './tmp'
    file_name = File.basename(base_file_name)
    file_name = Digest::SHA256.hexdigest(base_file_name) if file_name.length > MAX_FILENAME
    file_ext = File.extname(base_file_name)[0, MAX_EXTENSION]

    FileUtils.mkdir_p(tmp_dir) unless File.exist?(tmp_dir)
    tmp = Tempfile.new([file_name, file_ext], tmp_dir)
    tmp.binmode if bin_mode
    tmp
  end

  def delete_temp_file(file)
    begin
      file.close
    rescue Object
      nil
    end
    begin
      File.unlink(file)
    rescue Object
      nil
    end
  end
end
