# encoding: utf-8

require "net/http"
require 'digest/md5'
require "base64"

METADATA_PREFIX = 'x-upyun-meta-'
REST_REQUESTS={GET: Net::HTTP::Get, PUT: Net::HTTP::Put, DELETE: Net::HTTP::Delete,
              POST: Net::HTTP::Post, HEAD: Net::HTTP::Head}

METADATA_LIST = %w(x-upyun-width x-upyun-height x-upyun-frames x-upyun-file-type)

class FolderItem
  attr_accessor :file_name, :file_type, :size, :number
  def initialize(file_name, file_type, size, number)
    @file_name = file_name
    @file_type = file_type
    @size = size
    @number = number
  end
end

class UpYun
  attr_accessor :host, :username, :password, :bucket, :up_auth, :debug, :content_md5, :file_secret, :tmp_info

  def initialize(bucket, username, password, up_auth=false,host='v0.api.upyun.com',
                  debug=false, content_md5='', file_secret='')
    @host = host
    @username = username
    @password = password
    @bucket = bucket
    @up_auth = up_auth
    @debug = debug
    @content_md5 = content_md5
    @file_secret = file_secret
    @tmp_info = nil
  end

  #读取文件
  #path 所要读取文件地远程路径
  def read_file(path, headers={}, metadata={})
    response = send_http_request(:GET, path, '', headers, metadata)
    if response.code.eql? "200"
      return response.body
    else
      return nil
    end
  end

  #获取文件信息
  #path 文件的远程路径
  #返回格式为 {'date': unix time, 'type': file | folder, 'size': file size} 或 None
  def get_file_info(path, headers={}, metadata={})
    response = send_http_request(:HEAD, path, '', headers, metadata)
    if response.code.eql? "200"
      infos={}
      infos['type'] = response.header['x-upyun-file-type']
      infos['size'] = response.header['x-upyun-file-size']
      infos['date'] = response.header['x-upyun-file-date']
      return infos
    else
      return nil
    end
  end

  #获取某个目录的空间占用大小
  #path目录路径
  def get_usage(path='', headers={}, metadata={})
    response = send_http_request(:GET, "#{path}?usage", headers, metadata)
    begin
      usage = Integer(response.body)
    rescue
      usage = nil
    end
    return usage
  end

  #删除目录
  #path目录路径, 只允许空目录
  def rmdir(path, headers={}, metadata={})
    delete_file(path, headers, metadata)
  end

  #新建目录
  #path目录路径
  #[auto] 是否自动创建父级目录（最多10级）
  def mkdir(path, auto=false, headers={}, metadata={})
    headers['folder'] = 'create'
    if auto
      headers['mkdir'] = 'true'
    end
    check_response(send_http_request(:POST, path, '', headers, metadata))
  end

  #删除文件
  #path 所要删除文件地远程路径
  def delete_file(path, headers={}, metadata={})
    response = send_http_request(:DELETE, path, '', headers, metadata)
    check_response(response)
  end

  #获取上传文件后的信息（仅图片空间有返回数据）
  #key 信息字段名（x-upyun-width、x-upyun-height、x-upyun-frames、x-upyun-file-type）
  #return value or NULL
  def get_writed_file_info(key)
    unless @tmp_info.nil?
      return @tmp_info[key]
    else
      return nil
    end
  end

  #读取目录,返回FolderItem
  #path目录路径
  def read_dir(path='', headers={}, metadata={})
    response = send_http_request(:GET, path, '', headers, metadata)
    if response.code.eql? "200"
      result = response.body.gsub /[\t|\n]/, '\/'
      tmp_list = result.split('\/')
      i = 0
      file_list = []
      while (i + 1) < tmp_list.size
        fi = FolderItem.new(tmp_list[i], tmp_list[i+1], tmp_list[i+2], tmp_list[i+3])
        file_list << fi
        i += 4
      end
      return file_list
    else
      return nil
    end
  end

  #上传文件
  #data 要上传的文件数据
  #path 远程文件的位置
  #[auto] 是否自动创建父级目录（最多10级）
  def write_file(path, data, auto=false, headers={}, metadata={})
    if auto
      headers['mkdir'] = 'true'
    end

    unless data.nil?
      headers['Content-Length'] = data.size.to_s
    end

    response = send_http_request(:PUT,path, data, headers, metadata)
    if response.code.eql? "200"
      @tmp_info = {}
      METADATA_LIST.each do |meta|
        @tmp_info[meta] = response.header[meta]
      end
      return true
    else
      return false
    end
  end

  private

  def md5(data)
    Digest::MD5.hexdigest(data)
  end

  def check_response(response)
    if response.code.eql? "200"
      return true
    end
    return false
  end

  def send_http_request(methon, path, data='', headers={}, metadata={})
    full_path = "/#{@bucket}/#{path}"
    http = Net::HTTP.new(@host)
    complete_headers = generate_headers(methon.to_s, full_path, data, headers, metadata)
    request = REST_REQUESTS[methon].new(full_path, complete_headers)
    if data.is_a? File
      request.body_stream= data
    end

    http.request(request)
  end

  def merge_meta(headers, metadata)
    final_headers = headers.clone
    metadata.each_key do |key|
      final_headers["#{METADATA_PREFIX}#{key}"] = metadata[key]
    end
    final_headers
  end

  def add_upyun_auth_header(headers, method, uri)
    headers['Date'] = Time.now.gmtime.strftime("%a, %d %b %Y %X GMT")
    len = headers.include?('Content-Length') ? headers['Content-Length'].to_s : "0"

    scr = md5("#{method}&#{uri}&#{headers['Date']}&#{len}&#{md5(@password)}")

    headers['Authorization'] = "UpYun #@username:#{scr}"
  end


  def add_basic_auth_header(headers, username, password)
    encode = Base64.encode64("#{username}:#{password}")
    headers['Authorization'] = "Basic #{encode.to_s.strip}"
  end

  def generate_headers(method, path, data='', headers={}, metadata={})

    unless @content_md5.empty?
      headers['Content-MD5'] = @content_md5
      @content_md5 = ''
    end

    unless @file_secret.empty?
      headers['Content-Secret'] = @file_secret
      @file_secret = ''
    end

    final_headers = merge_meta(headers, metadata)

    if @up_auth
      add_upyun_auth_header(final_headers, method, path)
    else
      add_basic_auth_header(final_headers, @username, @password)
    end
    final_headers
  end
end