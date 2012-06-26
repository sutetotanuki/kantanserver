# -*- coding: utf-8 -*-
require "socket"
require "optparse"
require "logger"
require "timeout"
require "uri"
require 'cgi'

opt = OptionParser.new
opt.separator "options:"
opt.on("-p", "--port port number") { |num| $port = num }
opt.parse(ARGV)

$port ||= 80
$log = Logger.new(STDOUT)

CR   = "\x0d"
LF   = "\x0a"
CRLF = "\x0d\x0a"

class Request < Hash
  def initialize(socket)
    read_request_line(socket)
    read_header(socket)
    read_body(socket)
    parse_query(self['request-uri'].query)
  end

  def read_header(socket)
    while line = read_line(socket)
      break if line == CRLF
      extract_content_length(line)
    end
  end

  def read_body(socket)
    remaining_size = self['content-length'].to_i

    # とりあえず捨てる
    while remaining_size > 0
      data =  read_data(socket, remaining_size)
      remaining_size -= data.bytesize
    end
  end

  def extract_content_length(line)
    if /^(?<field>[A-Za-z0-9!\#$%&'*+\-.^_`|~]+):\s+(?<value>.*?)/ =~ line
      field.downcase!
      if field == "content-length"
        self['content-length'] = value
      end
    end
  end
 
  def read_request_line(socket)
    @request_line = read_line(socket)
    if /^(\S+)\s+(\S+)(?:\s+HTTP\/(\d+\.\d+))?\r?\n/mo =~ @request_line
      self['request-method'] = $1
      self['request-path']   = $2
      self['request-uri']    = URI($2)
      self['query-string']   = self['request-uri'].query
    else
      throw 'invalid uri.'
    end
  end

  def parse_query(str)
    query = {}

    if str
      str.split(/[&;]/).each do |x|
        next if x.empty?
        k, v = x.split('=', 2).map{ |x| URI.decode_www_form_component(x, Encoding::UTF_8) }
        query[k] = v
      end
    end

    self['query'] = query
  end

  def read_line(socket)
    socket.gets(LF, 4096)
  end
end

server = TCPServer.open($port)
addr = server.addr
$log.info("server is on #{addr[1]}")

loop do
  Thread.start(server.accept) do |socket|
    begin
      accept_time = Time.now
     
      $log.info("accept from: #{socket}")

      req = Request.new(socket)

      wait_time = req['query']['wait'].to_i

      sleep wait_time

      message = "Wait for #{wait_time}sec. #{accept_time} - #{Time.now}"

      socket.write("HTTP/1.1 200 OK #{CRLF}")
      socket.write("Content-type: text/plain; charset=utf-8#{CRLF}")
      socket.write("Content-length: #{message.bytesize}#{CRLF}")
      socket.write("Connection: close#{CRLF}")
      socket.write("Set-Cookie: num=1234; expires=#{CGI::rfc1123_date(Time.now + 3600)};#{CRLF}")
      socket.write(CRLF)
      socket.write(message)

      socket.close
    rescue => e
      socket.write("HTTP/1.1 500 Internal Server Error #{CRLF}")
      socket.write("Content-type: text/plain; charset=utf-8#{CRLF}")
      socket.write("Content-length: 6#{CRLF}")
      socket.write("Connection: close#{CRLF}")
      socket.write(CRLF)
      socket.write("muripo")
     
      $log.error(e)
    end
  end
end
