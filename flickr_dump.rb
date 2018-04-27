#!/usr/bin/env ruby
require 'yaml'
require 'byebug'
require 'flickraw'
require 'rubygems'
require 'mechanize'
require 'io/console'
require 'optparse'
require 'net/http'
require 'json'
require 'time'
require 'fileutils'

class FlickrDump
  SETTINGS_FILE = 'settings.yml'.freeze
  DEFAULT_PATH = './images'.freeze
  DEFAULT_PAGE_SIZE = 500

  def self.run(options)
    new(options).run
  end

  def initialize(options)
    @path = options['path'] || DEFAULT_PATH
    FileUtils.mkdir_p(@path) unless File.exist?(@path)

    FlickRaw.api_key = options['api_key']
    FlickRaw.shared_secret = options['api_secret']

    load_settings

    if @access_token.nil? || @access_secret.nil?
      authorize_account
    else
      flickr.access_token = @access_token
      flickr.access_secret = @access_secret
      puts "You are now authenticated as #{flickr.test.login.username}"
    end
  end

  def authorize_account
    token = flickr.get_request_token
    auth_url = flickr.get_authorize_url(token['oauth_token'], perms: 'read')

    puts "Open url in browser to complete authentication process: #{auth_url}"
    puts 'Copy here the number given when you complete the process.'
    verify = gets.strip

    flickr.get_access_token(token['oauth_token'], token['oauth_token_secret'], verify)
    puts "You are now authenticated as #{flickr.test.login.username}"

    save_credentials(flickr.access_token, flickr.access_secret)
  rescue FlickRaw::FailedResponse => e
    puts "Authentication failed : #{e.msg}"
  end

  def load_settings
    return unless File.file?(SETTINGS_FILE)

    settings = YAML.load_file(SETTINGS_FILE)
    @access_token = settings[:access_token]
    @access_secret = settings[:access_secret]
  end

  def save_settings(access_token: nil, access_secret: nil)
    settings = {
      access_token: access_token || @access_token,
      access_secret: access_secret || @access_secret,
    }
    File.open(SETTINGS_FILE, 'w') do |file|
      file.write settings.to_yaml
    end
  end

  def run
    flickr.photosets.getList.each do |photoset|
      download_photoset(photoset)
    end
  ensure
    save_settings
  end

  def download_photoset(photoset)
    puts "Downloading photos from photoset: #{photoset.title}"
    photoset_path = "#{@path}/#{photoset.title}"
    FileUtils.mkdir_p(photoset_path) unless File.exist?(photoset_path)

    page_num = 1
    until (photos = get_photoset_page(id: photoset['id'].to_i, page_num: page_num).photo).empty?
      photos.each do |photo|
        process_photo(photo: photo, photoset_path: photoset_path)
      end
      page_num += 1
    end
  end

  def get_photoset_page(id:, page_num:)
    flickr.photosets.getPhotos(
      photoset_id: id,
      page: page_num,
      per_page: DEFAULT_PAGE_SIZE
    )
  end

  def process_photo(photo: photo, photoset_path:)
    details = flickr.photos.getInfo(photo_id: photo['id'])
    date_taken = Time.parse(details.dates.taken)
    filename = (details.title == '' ? details.id : details.title) + '.' + details.originalformat
    filepath = "#{photoset_path}/#{filename}"

    if File.exist?(filepath)
      puts "Already downloaded photo: #{filepath}"
      sleep(1)
      return
    end

    sizes = flickr.photos.getSizes(photo_id: photo['id'])
    original = sizes.select { |s| s['label'] == 'Original' }.first

    download_file(url: original['source'], filepath: filepath)
    FileUtils.touch(filepath, mtime: date_taken)
    sleep(2)
  rescue => ex
    save_settings
    msg = "FAIL: photoid: #{photo['id']}\terror: #{ex}\n"
    puts msg
    open('log.txt', 'a') { |f| f << msg }
  end

  def download_file(url:, filepath:)
    return if url.nil? || url.length <= 0
    puts "Downloading: #{url}"
    agent.get(url).save(filepath)
  end

  def agent
    @agent ||= Mechanize.new
  end
end

def help_menu_and_exit
puts <<-"EOHELP"
Download all files from flickr:

Usage: #{__FILE__} --path=/path/to/download/location --api_key=apc123... --api_secret=somesecret --access_token=mytoken --access_secret=secret

OPTIONS
--path : /path/to/download/files/to
--api_key : API key for your flickr application
--api_secret : API secret for your flickr application
--help : help

EOHELP
  exit(0)
end

if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)
  options = {}
  parser = OptionParser.new do |opts|
    opts.on('-p', '--path path') do |path|
      options['path'] = path
    end

    opts.on('-k', '--api_key api_key') do |api_key|
      options['api_key'] = api_key
    end

    opts.on('-s', '--api_secret api_secret') do |api_secret|
      options['api_secret'] = api_secret
    end

    opts.on('-h', '--help', 'help menu') do
      help_menu_and_exit
    end
  end

  begin
    parser.parse!
    FlickrDump.run(options)
  rescue => ex
    puts ex
    puts ex.backtrace
    help_menu_and_exit
  end
end

