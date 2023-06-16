require "net/ftp"

puts "Start FTP test"

ftp = Net::FTP.new(nil, ssl: false)
ftp.passive = true
ftp.binary = true

ftp.connect("ftp.dlptest.com", "21")
p ftp.login("dlpuser", "rNrKYTX9g7z3RgJRmxWuGHbeu")

ftp.put("ftp-test.rb", "ftp-test.rb") do |chunk|
  p chunk
end

ftp.close if ftp && !ftp.closed?

puts "End FTP test"
