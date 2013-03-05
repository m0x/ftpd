#!/usr/bin/env ruby

unless $:.include?(File.dirname(__FILE__) + '/../lib')
  $:.unshift(File.dirname(__FILE__) + '/../lib')
end

require 'ftpd'
require 'optparse'

module Example

  # Command-line option parser

  class Arguments

    attr_reader :eplf
    attr_reader :interface
    attr_reader :port
    attr_reader :read_only
    attr_reader :tls

    def initialize(argv)
      @interface = 'localhost'
      @tls = :explicit
      @port = 0
      op = option_parser
      op.parse!(argv)
    rescue OptionParser::ParseError => e
      $stderr.puts e
      exit(1)
    end

    private

    def option_parser
      op = OptionParser.new do |op|
        op.on('-p', '--port N', Integer, 'Bind to a specific port') do |t|
          @port = t
        end
        op.on('-i', '--interface IP', 'Bind to a specific interface') do |t|
          @interface = t
        end
        op.on('--tls [TYPE]', [:off, :explicit, :implicit],
              'Select TLS support (off, explicit, implicit)') do |t|
          @tls = t
        end
        op.on('--eplf', 'LIST uses EPLF format') do |t|
          @eplf = t
        end 
        op.on('--read-only', 'Prohibit put, delete, rmdir, etc.') do |t|
          @read_only = t
        end
      end
    end

  end
end

module Example

  # The FTP server requires and instance of a _driver_ which can
  # authenticate users and create a file system drivers for a given
  # user.  You can use this as a template for creating your own
  # driver.

  class Driver

    # Your driver's initialize method can be anything you need.  Ftpd
    # does not create an instance of your driver.

    def initialize(user, password, data_dir, read_only)
      @user = user
      @password = password
      @data_dir = data_dir
      @read_only = read_only
    end

    # Return true if the user should be allowed to log in.
    # @param user [String]
    # @param password [String]
    # @return [Boolean]

    def authenticate(user, password)
      user == @user && password == @password
    end

    # Return the file system to use for a user.
    # @param user [String]
    # @return A file system driver that quacks like {Ftpd::DiskFileSystem}

    def file_system(user)
      if @read_only
        Ftpd::ReadOnlyDiskFileSystem
      else
        Ftpd::DiskFileSystem
      end.new(@data_dir)
    end

  end
end

module Example
  class Main

    include Ftpd::InsecureCertificate

    def initialize(argv)
      @args = Arguments.new(argv)
      @data_dir = Ftpd::TempDir.make
      create_files
      @driver = Driver.new(user, password, @data_dir, @args.read_only)
      @server = Ftpd::FtpServer.new(@driver)
      @server.interface = @args.interface
      @server.port = @args.port
      @server.tls = @args.tls
      @server.certfile_path = insecure_certfile_path
      if @args.eplf
        @server.list_formatter = Ftpd::ListFormat::Eplf
      end
      @server.start
      display_connection_info
      create_connection_script
    end

    def run
      wait_until_stopped
    end

    private

    HOST = 'localhost'

    def create_files
      create_file 'README',
      "This file, and the directory it is in, will go away\n"
      "When this example exits.\n"
    end

    def create_file(path, contents)
      full_path = File.expand_path(path, @data_dir)
      FileUtils.mkdir_p File.dirname(full_path)
      File.open(full_path, 'w') do |file|
        file.write contents
      end
    end

    def display_connection_info
      puts "Interface: #{@server.interface}"
      puts "Port: #{@server.bound_port}"
      puts "User: #{user}"
      puts "Pass: #{password}"
      puts "TLS: #{@args.tls}"
      puts "Directory: #{@data_dir}"
      puts "URI: ftp://#{HOST}:#{@server.bound_port}"
    end

    def create_connection_script
      command_path = '/tmp/connect-to-example-ftp-server.sh'
      File.open(command_path, 'w') do |file|
        file.puts "#!/bin/bash"
        file.puts "ftp $FTP_ARGS #{HOST} #{@server.bound_port}"
      end
      system("chmod +x #{command_path}")
      puts "Connection script written to #{command_path}"
    end

    def wait_until_stopped
      puts "FTP server started.  Press ENTER or c-C to stop it"
      $stdout.flush
      begin
        gets
      rescue Interrupt
        puts "Interrupt"
      end
    end

    def user
      ENV['LOGNAME']
    end

    def password
      ''
    end

  end
end

Example::Main.new(ARGV).run if $0 == __FILE__
