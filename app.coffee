fs            = require('fs')
app           = require('express').createServer()
io            = require('socket.io').listen(app)
createBuilder = require('./builder')
nats       = require('nats').connect()
temp = require('temp')
path = require('path')

local_address = null
b = null

require('dns').lookup require('os').hostname(), (err, add, fam) ->
  local_address = add

app.listen 8081

app.get '/', (req,res) ->
  res.sendfile __dirname+'/index.html'

nats.subscribe "claw.builder.worker", { queue: 'worker' }, (msg,reply) ->
  message = JSON.parse(msg)
  reply_message = { url: 'http://'+local_address+':8081' }
  nats.publish reply, JSON.stringify(reply_message)

  b = createBuilder(message)
  b.on 'data', (d) ->
    process.stdout.write d
  b.on 'done', (output) ->
    nats.publish message.notify_subj, JSON.stringify(output)
  b.process()

io.sockets.on 'connection', (socket) ->
  socket.emit 'update', {data: "hello\n"}
  if b
    b.on 'data', (d) ->
      socket.emit 'update', { data: d }
    b.on 'done', (c) ->
      socket.emit 'update', { data: 'exit '+c+"\n" }
