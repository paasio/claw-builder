fs            = require('fs')
path          = require('path')
temp          = require('temp')
nats          = require('nats').connect()
app           = require('express').createServer()
io            = require('socket.io').listen(app)
createBuilder = require('./builder')
jshashtable   = require('./support/jshashtable')

local_address = "localhost"
#require('dns').lookup require('os').hostname(), (err, add, fam) ->
#  local_address = add

BUILDS = new jshashtable.Hashtable()
MAX_BUILDS_RUNNING = 8
RUNNING_BUILDS     = 0

app.listen 8081

nats.subscribe 'claw.builder.discover', ->
  nats.publish 'claw.builder.announce', JSON.stringify({host:"#{local_address}:8081"})

nats.subscribe "claw.builder.worker", (msg,reply) ->
  return if RUNNING_BUILDS >= MAX_BUILDS_RUNNING
  message = JSON.parse(msg)

  builder = createBuilder(message.manifest)
  builder.on 'data', (data) ->
    io.sockets.emit 'update', { task_id: message.task_id, data: data }
  builder.on 'done', (output) ->
    complete_message = {
      task_id: message.task_id,
      package_url: output.package_url,
      success: output.success
    }
    io.sockets.emit 'complete', complete_message
    RUNNING_BUILDS -= 1
    BUILDS.remove message.task_id
  RUNNING_BUILDS += 1
  BUILDS.put message.task_id, builder

  reply_message = {
    task_id: message.task_id
    host: "#{local_address}:8081"
  }
  nats.publish reply, JSON.stringify(reply_message)

io.sockets.on 'connection', (socket) ->
  socket.on 'process', (data) ->
    builder = BUILDS.get data.task_id
    builder.process() if builder

nats.publish 'claw.builder.announce', JSON.stringify({host:"#{local_address}:8081"})
