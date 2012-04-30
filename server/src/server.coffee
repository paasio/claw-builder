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

    # configure updates to broadcast
    conn.on 'update', (data) ->
      io_server.sockets.in(data.task_id).emit('update', data)
    
    # broadcast completion methods
    conn.on 'complete', (data) ->
      io_server.sockets.in(data.task_id).emit('complete', data)

      # get the redis entry and update the state and url
      rc.get "cb.task.#{data.task_id}", (e,t) ->
        t = JSON.parse t
        t.state = 'complete'
        t.package_url = data.package_url
        rc.set "cb.task.#{data.task_id}", JSON.stringify(t)

    BUILDERS[host] = conn
  BUILDERS[host]

rc = redis.createClient();

app.listen 8080
app.use express.bodyParser()
app.use express.static("#{__dirname}/public")
app.set "view engine", "html"
app.register ".html", require("jqtpl").express

# main page
app.get '/', (req,res) ->
  # get tasks
  rc.smembers 'cb.tasks', (e,task_ids) ->
    # convert into keys
    async.map(task_ids, (i,cb) ->
      cb null, "cb.task.#{i}"
    , (e,task_idz) ->
      # mget the task keys
      rc.mget task_idz, (e,taskss) ->
        # convert into objects
        async.map(taskss || [], (i,cb) ->
          # transform a bit
          t = JSON.parse(i)
          t.timestamp = new Date(t.timestamp)
          cb null, t
        , (e,tasks) ->
          # render
          res.render 'index.html', { layout: false, tasks: tasks }
        )
    )

# trigger a new build
app.post '/build', (req,res) ->
  task_id = uuid.v4()
  message = {
    task_id: task_id
    manifest: req.body
  }

  # add to redis
  task = {
    task_id: task_id,
    timestamp: (new Date).getTime(),
    manifest: message.manifest,
    state: 'pending'
  }
  rc.sadd 'cb.tasks', task_id
  rc.set "cb.task.#{task_id}", JSON.stringify(task)

  nats.request 'claw.builder.worker', JSON.stringify(message), {max:1}, (reply_json) ->
    reply = JSON.parse(reply_json)
    res.send({ url: "http://#{req.headers.host}", channel: task_id })
    
    task.host = reply.host
    task.state = 'running'
    rc.set "cb.task.#{task_id}", JSON.stringify(task)

    builder = get_host(reply.host)
    builder.emit 'process', { task_id: task_id }

# socket.io handler
io_server.sockets.on 'connection', (socket) ->
  # subscribe to a build output
  socket.on 'subscribe', (data) ->
    socket.join(data.build)

# set up subscription for worker announcements
nats.subscribe 'claw.builder.announce', (msg) ->
  message = JSON.parse(msg)
  get_host(message.host)

# we're up and ready, discover all workers
nats.publish 'claw.builder.discover', ''
