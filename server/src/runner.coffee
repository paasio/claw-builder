fs           = require('fs')
spawn        = require('child_process').spawn
EventEmitter = require('events').EventEmitter;

class Runner extends EventEmitter
  constructor: (@script, @options) ->
    @options = {} if !@options

  run: () ->
    @runner = spawn 'bash', ['-c', @script], {
        cwd: @options.cwd || __dirname
        env: @options.env || {}
      }

    if @options.log
      @log = fs.createWriteStream(@options.log)
      @runner.stdout.pipe @log
      @runner.stderr.pipe @log
      @runner.on 'exit', (code) =>
        @log.end()

    @runner.stdout.on 'data', (data) =>
      this.emit 'stdout', data.toString()

    @runner.stderr.on 'data', (data) =>
      this.emit 'stderr', data.toString()

    @runner.on 'exit', (code) =>
      this.emit 'exit', code

createRunner = (script, options) -> new Runner script, options
module.exports = createRunner
