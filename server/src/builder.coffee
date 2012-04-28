crypto       = require('crypto')
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

    # normalize the nodejs arch
    switch require('os').arch()
      when 'x64'  then @arch = 'x86_64'
      when 'ia32' then @arch = 'i386'
    @build_arch = @arch
    @build_arch = 'all' if @spec.noarch

    # file info
    @workingDirectory = temp.mkdirSync('working')
    @packageDirectory = temp.mkdirSync('package')
    @packageBaseName  = "#{@spec.name}-#{@spec.version}-#{@arch}.tar.gz"
    @packageFilename  = temp.path({suffix: '.tar.gz'});

    # setup s3 client
    @s3_client = knox.createClient({
      key: process.env.S3_KEY,
      secret: process.env.S3_SECRET,
      bucket: process.env.S3_BUCKET
    })
    @s3_path = "#{@spec.name}/#{@packageBaseName}"

  process: ->
    @_downloadSources()

  _downloadSources: ->
    # download each source
    async.forEachSeries(@spec.sources, (source, clbk) =>
      if source.arch
        return clbk() if source.arch != @arch
      this.emit 'data', "Downloading #{source.url}\n"
      @_downloadFile source, (path) =>
        async.forEach(['md5','sha1','sha256'], (algo,vcb) =>
          if source[algo]
            @_validateFile path, algo, source[algo], vcb
          else
            vcb()
        , (err) =>
          if err
            clbk(err)
          else
            clbk()
        )
    , (err) =>
      if err
        @_finish(false, err)
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
        # generate checksums
        this.emit 'data', "Generating checksums...\n"
        @output.checksums = {}
        async.forEachSeries(['md5','sha1','sha256'], (algo,cb) =>
          @_checksumFile @packageFilename, algo, (c) =>
            @output.checksums[algo] = c
            cb()
        , =>
          # send it to s3 if it exited ok
          this.emit 'data', "Uploading to S3...\n"
          @s3_client.putFile @packageFilename, @s3_path, (err,res) =>
            @output.package_url = @s3_client.url(@s3_path)
            @_finish(true)
        )
    runner.run()

  _finish: (success, err) ->
    # cleanup and emit we're done
    wrench.rmdirSyncRecursive @workingDirectory
    wrench.rmdirSyncRecursive @packageDirectory
    @output.success = success
    @output.error_message = err if !success
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
      path: parsed_url.path
    }

    filename = source.name || parsed_url.pathname.split('/').pop()
    file     = fs.createWriteStream("#{@workingDirectory}/#{filename}")

    http.get options, (res) =>
      res.pipe(file)
      res.on 'end', =>
        cb "#{@workingDirectory}/#{filename}" if cb

  _checksumFile: (path,algo,cb) ->
    hash = crypto.createHash algo
    file = fs.createReadStream path
    file.on 'data', (data) =>
      hash.update data
    file.on 'end', =>
      cb hash.digest('hex')

  _validateFile: (path,algo,expected,cb) ->
    @_checksumFile path, algo, (checksum) =>
      if checksum == expected
        cb()
      else
        cb("#{algo} for #{path.split('/').pop()} checksum didn't match")

createBuilder = (spec) -> new Builder spec
module.exports = createBuilder
