fs        = require('fs')
uuid      = require('node-uuid')
nats      = require('nats').connect()
express   = require('express')
io_client = require('socket.io-client')
io_server = require('socket.io')
redis     = require('redis')
async     = require('async')
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
  rc.get "cb.task.#{data.task_id}", (e,t) ->
    t = JSON.parse t
    t.state = 'complete'
    t.package_url = data.package_url
    rc.set "cb.task.#{data.task_id}", JSON.stringify(t)
  console.log 'COMPLETE:'
  console.log data

nats.subscribe 'claw.builder.announce', (msg) ->
  message = JSON.parse(msg)
  get_host(message.host)

rc = redis.createClient();

app.listen 8080
app.use express.bodyParser()
app.use express.static("#{__dirname}/public")
app.set "view engine", "html"
app.register ".html", require("jqtpl").express

app.get '/', (req,res) ->
  rc.smembers 'cb.tasks', (e,task_ids) ->
    async.map(task_ids, (i,cb) ->
      cb null, "cb.task.#{i}"
    , (e,task_idz) ->
      rc.mget task_idz, (e,taskss) ->
        async.map(taskss || [], (i,cb) ->
          t = JSON.parse(i)
          t.timestamp = new Date(t.timestamp)
          cb null, t
        , (e,tasks) ->
          console.log tasks
          res.render 'index.html', { layout: false, tasks: tasks }
        )
    )

app.post '/build', (req,res) ->
  task_id = uuid.v4()
  rc.sadd 'cb.tasks', task_id
  message = {
    task_id: task_id
    manifest: req.body
  }
  task = {
    task_id: task_id,
    timestamp: (new Date).getTime(),
    manifest: message.manifest,
    state: 'pending'
  }
  rc.set "cb.task.#{task_id}", JSON.stringify(task)

  nats.request 'claw.builder.worker', JSON.stringify(message), {max:1}, (reply_json) ->
    reply = JSON.parse(reply_json)
    res.send({ url: "http://localhost:8080", channel: task_id })
    
    task.host = reply.host
    task.state = 'running'
    rc.set "cb.task.#{task_id}", JSON.stringify(task)

    builder = get_host(reply.host)
    builder.emit 'process', { task_id: task_id }


io_server.sockets.on 'connection', (socket) ->
  socket.on 'subscribe', (data) ->
    socket.join(data.build)

nats.publish 'claw.builder.discover', ''
