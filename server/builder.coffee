fs           = require('fs')
path         = require('path')
url          = require('url')
http         = require('http')
async        = require('async')
temp         = require('temp')
wrench       = require('wrench')
knox         = require('knox')
EventEmitter = require('events').EventEmitter;
createRunner = require('./runner')

class Builder extends EventEmitter
  constructor: (@spec) ->
    @output = {}

    # file info
    @workingDirectory = temp.mkdirSync('working')
    @packageDirectory = temp.mkdirSync('package')
    @packageFilename = "#{@packageDirectory}/#{@spec.name}-#{@spec.version}.tar.gz"

    # sources seems to not be an array if there is only one element
    if @spec.sources not instanceof Array
      @spec.sources = [ @spec.sources ]

    # setup s3 client
    @s3_client = knox.createClient({
      key: process.env.S3_KEY,
      secret: process.env.S3_SECRET,
      bucket: process.env.S3_BUCKET
    })
    @s3_path = "#{@spec.name}/#{@spec.name}-#{@spec.version}.tar.gz"

  process: ->
    if @spec.sources
      @_downloadSources()
    else
      @_runBuild()

  _downloadSources: ->
    # download each source
    async.forEach(@spec.sources, (source, clbk) =>
      this.emit 'data', "Downloading #{source.url}\n"
      @_downloadFile(source, clbk)
    , (err) =>
      if err
        @_finish(false)
      else
        @_runBuild()
    )

  _runBuild: ->
    # execute build
    log = temp.path {suffix:'.log'}
    # always ensure set -e/-x
    runner = createRunner "set -e\nset -x\n#{@spec.build_script}",
      {
        log: log,
        cwd: @workingDirectory,
        env: {
          'CLAW_PACKAGE_DIRECTORY': @packageDirectory,
          'CLAW_WORKING_DIRECTORY': @workingDirectory
        }
      }
    @_setupRunner(runner)
    runner.on 'exit', (code) =>
      if path.existsSync(log)
        @output.build_log = fs.readFileSync(log).toString()
      if code == 0
        @_runPackaging()
      else
        @_finish(false)
    runner.run()

  _runPackaging: ->
    # package it up
    log = temp.path {suffix:'.log'}
    runner = createRunner "set -x\ntar czvf ${TEMP_PACKAGE_FILE} .",
      {
        log: log,
        cwd: @packageDirectory,
        env: {
          'CLAW_PACKAGE_DIRECTORY': @packageDirectory,
          'TEMP_PACKAGE_FILE': @packageFilename
        }
      }
    @_setupRunner(runner)
    runner.on 'exit', (code) =>
      if path.existsSync(log)
        @output.packaging_log = fs.readFileSync(log).toString()
      if code == 0
        # send it to s3 if it exited ok
        this.emit 'data', "Uploading to S3...\n"
        @s3_client.putFile @packageFilename, @s3_path, (err,res) =>
          @output.package_url = @s3_client.url(@s3_path)
          @_finish(true)
    runner.run()

  _finish: (success) ->
    # cleanup and emit we're done
    wrench.rmdirSyncRecursive @workingDirectory
    wrench.rmdirSyncRecursive @packageDirectory
    @output.success = success
    this.emit 'done', @output

  _setupRunner: (runner) ->
    # setup piping of data upstream
    runner.on 'stdout', (data) =>
      this.emit 'data', data
    runner.on 'stderr', (data) =>
      this.emit 'data', data

  _downloadFile: (source, cb) ->
    parsed_url = url.parse(source.url)
    options = {
      host: parsed_url.host,
      port: parsed_url.port || 80
      path: parsed_url.pathname
    }

    filename = source.name || parsed_url.pathname.split('/').pop()
    file     = fs.createWriteStream("#{@workingDirectory}/#{filename}")

    http.get options, (res) =>
      res.pipe(file)
      res.on 'end', =>
        cb() if cb

createBuilder = (spec) -> new Builder spec
module.exports = createBuilder
