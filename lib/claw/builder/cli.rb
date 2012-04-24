require 'digest/sha1'
require 'yaml'

require 'rest_client'
require 'thor'

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
    load formula
    klass = File.read(formula)[/class (\w+)/, 1]
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
    puts "R: #{res.inspect}"

    puts ">> Building"
    puts ">> Build complete"
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
