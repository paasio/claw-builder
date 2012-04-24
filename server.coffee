fs      = require('fs')
uuid    = require('node-uuid')
nats    = require('nats').connect()
express = require('express')
io      = require('socket.io-client')
app     = express.createServer()

app.listen 8080
app.use express.bodyParser()

app.post '/build', (req,res) ->
  console.log req.body
  console.log req.files
  res.send('ok')
  return
  packaging_script = fs.readFileSync(req.files.packaging.path).toString()
  task_id = uuid.v4()
  message = {
    task_id: task_id
    packaging: packaging_script,
    upload_uri: 'elsewhere'
  }

  nats.request 'claw.builder.worker', JSON.stringify(message), {max:1}, (reply_json) ->
    console.log 'REPLY:'+reply_json
    reply = JSON.parse(reply_json)

    builder = io.connect(reply.url)
    builder.on 'connect', () ->
      builder.emit 'process', { task_id: task_id }
    builder.on 'update', (data) ->
      process.stdout.write data.data
    builder.on 'complete', (data) ->
      console.log 'COMPLETE: '+data
      builder.disconnect()

  res.send('ok')

