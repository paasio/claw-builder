fs            = require('fs')
app           = require('express').createServer()
io            = require('socket.io').listen(app)
createBuilder = require('./builder')
nats          = require('nats').connect()
temp          = require('temp')
path          = require('path')

local_address = null
require('dns').lookup require('os').hostname(), (err, add, fam) ->
  local_address = add

BUILDS = {}
build_running = false

app.listen 8081

app.get '/', (req,res) ->
  res.sendfile __dirname+'/index.html'

nats.subscribe "claw.builder.worker", { queue: 'worker' }, (msg,reply) ->
  return if build_running
  message = JSON.parse(msg)

  builder = createBuilder(message)
  builder.on 'data', (data) ->
    process.stdout.write data
    io.sockets.emit 'update', { task_id: message.task_id, data: data }
  builder.on 'done', (output) ->
    io.sockets.emit 'complete', { task_id: message.task_id, success: output.success }
    build_running = false
    BUILDS[message.task_id] = null
  BUILDS[message.task_id] = builder

  reply_message = {
    task_id: message.task_id
    url: "http://#{local_address}:8081"
  }
  nats.publish reply, JSON.stringify(reply_message)

io.sockets.on 'connection', (socket) ->
  socket.emit 'update', { data: "hello\n" }
  socket.on 'process', (data) ->
    if BUILDS[data.task_id]
      build_running = true
      BUILDS[data.task_id].process()
