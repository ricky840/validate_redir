#!/usr/bin/env ruby

# require 'pry'
require 'nokogiri'
require 'uri'
require 'net/http'

DEFAULT_PORT = 80
DEFAULT_SCHEME = "http"
HTTP_TIMEOUT = 5

unless ARGV.length == 1
  puts "\n"
  puts "Usage:"
  puts "   validate.rb FILENAME"
  puts "\n"
  exit
end

FILENAME = ARGV[0]
begin
  fd = File.open(FILENAME)
rescue => e
  puts e.message
  # puts e.backtrace
  exit
end

def validate_domain(domain)
  if domain =~ /^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}$/
    return domain
  else
    puts "The hostname entered is not in the right format. Bye!"
    exit
  end
end

def prepend(xml_file, str)
  new_content = ""
  File.open(xml_file, "r") do |file|
    content = file.read
    new_content = str + "\n" << content
  end

  File.open(xml_file, "w") do |file|
    file.write(new_content)
  end
end

def endpend(xml_file, str)
  File.open(xml_file, "a") do |file|
    file << str + "\n"
  end
end

def validate_url(url)
  uri = URI.parse(url)
  if not uri.scheme
    uri.scheme = DEFAULT_SCHEME
    uri.port = DEFAULT_PORT
  end

  if not uri.host or uri.host.empty?
    uri.host = DEFAULT_HOST
  end

  if not uri.path or uri.path.empty?
    uri.path = "/"
  end

  if not uri.path.chars[0] == "/"
    uri.path = "/" + uri.path
  end

  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = HTTP_TIMEOUT
  if uri.scheme == "https"
    http.use_ssl = true
  end

  begin
    req = Net::HTTP::Get.new(uri.path)
    res = http.request(req)
    return res
  rescue => e
    puts e.message
  end
end

puts "In case there is no host specified in the tag, please enter host(domain)name: "
DEFAULT_HOST = validate_domain(STDIN.gets.chomp)

doc = Nokogiri::XML(fd)
if not doc.root.name.to_s == "dummy"
  prepend(FILENAME, "<dummy>")
  endpend(FILENAME, "</dummy>")
  fd.close
  fd = File.open(FILENAME)
  doc = Nokogiri::XML(fd)
end

redirs = doc.css("destination")
dest_urls = Hash.new
dest_urls_wo_dynamic = Hash.new
redirs.each do |node|
  dest_urls[node.content] = node.line.to_s + node.path.to_s
  if not node.content.to_s.include? "%"
    dest_urls_wo_dynamic[node.content] = node.line.to_s + node.path.to_s
  end
end

puts "#{dest_urls.size} number of redirection rules are found"
puts "#{dest_urls_wo_dynamic.size} number of static redirection rules are found"
puts "Validating destinations"

hash_results = Hash.new

dest_urls_wo_dynamic.each_with_index do |obj, index|
  arr_results = Array.new
  destination = obj[0]
  path = obj[1]
  line_num = path.split("/")[0]

  if destination.include? "="
    destination = destination.gsub(/=/, '')
  end

  puts "\n#{index + 1}/#{dest_urls_wo_dynamic.size} Testing:#{line_num} #{destination}"
  response = validate_url(destination)
  if not response == nil
    arr_results.push(destination + "|" + response.code)

    loop_check = 0

    while response.code =~ /30[1|2|7]/
      loop_check += 1
      if loop_check == 10
        arr_results.push(destination + "|" + "RedirLoop")
        puts "Error: Redirection loop"
        break
      end
      if response.to_hash.has_key?("location")
        destination = response.to_hash["location"][0].to_s.strip
      end
      puts "#{response.code} Redirection received. Requesting back #{destination}"
      response = validate_url(destination)
      if response == nil
        arr_results.push(destination + "|" + "ErrNoRes")
        puts "Error: no response was received"
        break
      end
      arr_results.push(destination + "|" + response.code)
    end

    #temporary :(
    if not response == nil
      puts "#{response.code} #{destination}"
      hash_results[line_num] = arr_results
    end

  elsif response == nil
    arr_results.push(destination + "|" + "ErrNoRes")
    puts "Error: no response was received"
    next
  end
end

puts "\nPrinting results"
hash_results.each do |line, urls|
  msg = ""
  urls.each do |url|
    msg = msg + url + " "
  end
  puts "##{line} #{msg}"
end
