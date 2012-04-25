require 'digest/sha1'
require 'yaml'

require 'rest_client'
require 'thor'
require 'SocketIO'

require 'claw/builder'
require 'claw/builder/package_formula'

class Claw::Builder::CLI < Thor

  desc "build FORMULA", <<-DESC
Build a package using the FORMULA file given.

  DESC

  def build(formula)
    error("Formula file doesn't exist") unless File.exists?(formula)

    server  = ENV["MAKE_SERVER"] || "http://localhost:8080"

    # load the formula
    Dir.chdir File.dirname(File.expand_path(formula))
    $:.unshift File.expand_path('.')
    load File.basename(formula)
    klass = File.read(File.basename(formula))[/class (\w+)/, 1]
    spec = eval(klass).to_spec

    # create build manifest
    manifest = spec.dup
    manifest[:included_files] = []
    spec[:included_files].each do |file|
      io = File.open(file[:path], 'rb')
      manifest[:included_files] << io
    end

    # initiate the build
    puts ">> Uploading code for build"
    res = RestClient.post "http://localhost:8080/build", manifest
    res = JSON.parse(res)

    puts ">> Tailing build..."
    done_building = false
    client = SocketIO.connect(res['url'], :sync => true) do
      before_start do
        on_event('update') { |data| print data.first['data'] }
        on_event('complete') do |data|
          done_building = true
          if data.first['success']
            puts ">> Build complete"
            puts "   Build available from #{data.first['package_url']}"
          else
            puts ">> Build FAILED!"
          end
        end
      end
      after_start do
        emit("subscribe", { 'build' => res['channel'] })
      end
    end

    loop do
      break if done_building
      sleep 0.5
    end
  rescue Interrupt
    error "Aborted by user"
  rescue Errno::EPIPE
    error "Could not connect to build server: #{server}"
  end

private

  def error(message)
    puts "!! #{message}"
    exit 1
  end

end
