fs            = require('fs')
path          = require('path')
temp          = require('temp')
nats          = require('nats').connect()
app           = require('express').createServer()
io            = require('socket.io').listen(app)
createBuilder = require('./builder')

#local_address = null
#require('dns').lookup require('os').hostname(), (err, add, fam) ->
#  local_address = add

BUILDS = {}
build_running = false

app.listen 8081

app.get '/', (req,res) ->
  res.sendfile __dirname+'/index.html'

nats.subscribe "claw.builder.worker", (msg,reply) ->
  return if build_running
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
    build_running = false
    BUILDS[message.task_id] = null
  BUILDS[message.task_id] = builder

  reply_message = {
    task_id: message.task_id
    url: "http://localhost:8081"
  }
  console.log 'woot'
  nats.publish reply, JSON.stringify(reply_message)

io.sockets.on 'connection', (socket) ->
  socket.emit 'update', { data: "hello\n" }
  socket.on 'process', (data) ->
    if BUILDS[data.task_id]
      build_running = true
      BUILDS[data.task_id].process()
