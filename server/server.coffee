fs      = require('fs')
uuid    = require('node-uuid')
nats    = require('nats').connect()
express = require('express')
io      = require('socket.io-client')
app     = express.createServer()

app.listen 8080
app.use express.bodyParser()

app.get '/', (req,res) ->
  res.sendfile __dirname+'/index.html'

app.post '/build', (req,res) ->
  task_id = uuid.v4()
  message = {
    task_id: task_id
    manifest: req.body,
    upload_uri: 'elsewhere'
  }

  nats.request 'claw.builder.worker', JSON.stringify(message), {max:1}, (reply_json) ->
    console.log reply_json
    reply = JSON.parse(reply_json)

    builder = io.connect(reply.url)
    builder.on 'connect', () ->
      builder.emit 'process', { task_id: task_id }
    builder.on 'reconnect', () ->
      console.log 'reconnected'
    builder.on 'update', (data) ->
      process.stdout.write data.data
    builder.on 'complete', (data) ->
      console.log 'COMPLETE:'
      console.log data
      builder.disconnect()

  res.send()

