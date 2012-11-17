# encoding: utf-8
load  "./upyun.rb"

u = UpYun.new('空间名','用户名','密码', up_auth=true)


data = File.open("/tmp/code.jpg", "r")

img = "/test/ruby.jpg"
res = u.write_file(img, data, true)
#res = u.deleteFile("/code.jpg")

if res
  puts "upload pass"
else
  puts "upload fails"
  exit 1
end

pic = u.read_file(img)
file = File.new("/tmp/tmp.jpg", "w")
file.syswrite(pic)
file.close

usage = u.get_usage('/')
puts "usage: #{usage}"

puts u.get_writed_file_info('x-upyun-width')

puts u.get_file_info(img)

files = u.read_dir('/')
unless files.nil?
  files.each do |file|
    puts file.file_name
  end
end


res = u.delete_file(img)

if res
  puts "delete pass"
else
  puts "delete fails"
  exit 1
end
