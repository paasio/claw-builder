fs = require('fs')
temp = require('temp')
path = require('path')
wrench           = require('wrench')
createRunner = require('./runner')
EventEmitter = require('events').EventEmitter;

class Builder extends EventEmitter
  constructor: (@spec) ->
    @output = {}
    @workingDirectory = temp.mkdirSync('working')
    @packageDirectory = temp.mkdirSync('package')

  process: ->
    if @spec.pre_packaging
      @_runPrePackaging()
    else
      @_runPackaging()

  _runPrePackaging: ->
    log = temp.path {suffix:'.log'}
    runner = createRunner @spec.pre_packaging,
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
        @output.pre_packaging_log = fs.readFileSync(log).toString()
      if code == 0
        @_runPackaging()
      else
        @_finish(false)
    runner.run()

  _runPackaging: ->
    log = temp.path {suffix:'.log'}
    runner = createRunner @spec.packaging,
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
        @output.packaging_log = fs.readFileSync(log).toString()
      if code == 0
        @_runWrapup()
      else
        @_finish(false)
    runner.run()

  _runWrapup: ->
    log = temp.path {suffix:'.log'}
    runner = createRunner "set -x\ntar czvf ${TEMP_PACKAGE_FILE} .",
      {
        log: log,
        cwd: @packageDirectory,
        env: {
          'CLAW_PACKAGE_DIRECTORY': @packageDirectory,
          'TEMP_PACKAGE_FILE': '/Users/ken/source/paasio/claw/builder/done.tar.gz'
        }
      }
    @_setupRunner(runner)
    runner.on 'exit', (code) =>
      if path.existsSync(log)
        @output.tar_log = fs.readFileSync(log).toString()
      @_finish(code == 0)
    runner.run()

  _finish: (success) ->
    wrench.rmdirSyncRecursive @workingDirectory
    wrench.rmdirSyncRecursive @packageDirectory
    @output.success = success
    this.emit 'done', @output

  _setupRunner: (runner) ->
    runner.on 'stdout', (data) =>
      this.emit 'data', data
    runner.on 'stderr', (data) =>
      this.emit 'data', data

createBuilder = (spec) -> new Builder spec
module.exports = createBuilder
