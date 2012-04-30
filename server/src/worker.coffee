fs            = require('fs')
path          = require('path')
temp          = require('temp')
nats          = require('nats').connect()
app           = require('express').createServer()
io            = require('socket.io').listen(app)
createBuilder = require('./builder')
jshashtable   = require('./support/jshashtable')

local_address = "localhost"

# some basic globals
BUILDS = new jshashtable.Hashtable()
MAX_BUILDS_RUNNING = 8
RUNNING_BUILDS     = 0

# discover is used when the main server starts up to locate workers
nats.subscribe 'claw.builder.discover', ->
  nats.publish 'claw.builder.announce', JSON.stringify({host:"#{local_address}:8081"})

# it wants us to do some work
nats.subscribe "claw.builder.worker", (msg,reply) ->
  # return if we're running enough jobs already
  return if RUNNING_BUILDS >= MAX_BUILDS_RUNNING
  message = JSON.parse(msg)

  # create the builder and wire up events
  builder = createBuilder(message.manifest)
  builder.on 'data', (data) ->
    io.sockets.emit 'update', { task_id: message.task_id, data: data }
  builder.on 'done', (output) ->
    # tell the server we're finished
    complete_message = {
      task_id: message.task_id,
      package_url: output.package_url,
      success: output.success,
      checksums: output.checksums,
      error_message: output.error_message
    }
    io.sockets.emit 'complete', complete_message

    # decrement running builds
    RUNNING_BUILDS -= 1
    BUILDS.remove message.task_id

  # increment running builds
  RUNNING_BUILDS += 1
  BUILDS.put message.task_id, builder

  # reply back to the server that we're ready to run
  # doesn't begin until it connects though
  reply_message = {
    task_id: message.task_id
    host: "#{local_address}:8081"
  }
  nats.publish reply, JSON.stringify(reply_message)

app.listen 8081
io.sockets.on 'connection', (socket) ->
  socket.on 'process', (data) ->
    # process the build
    builder = BUILDS.get data.task_id
    builder.process() if builder

# at the end, look up our IP address and then announce availability
require('dns').lookup require('os').hostname(), (err, add, fam) ->
  local_address = add
  nats.publish 'claw.builder.announce', JSON.stringify({host:"#{local_address}:8081"})
