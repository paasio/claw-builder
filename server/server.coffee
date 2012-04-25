fs        = require('fs')
uuid      = require('node-uuid')
nats      = require('nats').connect()
express   = require('express')
io_client = require('socket.io-client')
io_server = require('socket.io')
app       = express.createServer()
io_server = require('socket.io').listen(app)

BUILDERS = {}

get_host = (host) ->
  if !BUILDERS[host]
    conn = io_client.connect("http://#{host}")
    conn.on 'update', output
    conn.on 'complete', complete
    BUILDERS[host] = conn
  BUILDERS[host]

output = (data) ->
  io_server.sockets.in(data.task_id).emit('update', data)

complete = (data) ->
  io_server.sockets.in(data.task_id).emit('complete', data)
  console.log 'COMPLETE:'
  console.log data

nats.subscribe 'claw.builder.announce', (msg) ->
  message = JSON.parse(msg)
  get_host(message.host)

app.listen 8080
app.use express.bodyParser()

app.get '/', (req,res) ->
  res.sendfile __dirname+'/index.html'

app.post '/build', (req,res) ->
  task_id = uuid.v4()
  message = {
    task_id: task_id
    manifest: req.body
  }

  nats.request 'claw.builder.worker', JSON.stringify(message), {max:1}, (reply_json) ->
    reply = JSON.parse(reply_json)
    res.send({ url: "http://localhost:8080", channel: task_id })

    builder = get_host(reply.host)
    builder.emit 'process', { task_id: task_id }


io_server.sockets.on 'connection', (socket) ->
  socket.on 'subscribe', (data) ->
    console.log 'subscription'
    console.log data
    socket.join(data.build)

nats.publish 'claw.builder.discover', ''
