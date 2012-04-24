fs = require('fs')
nats = require('nats').connect()
express = require('express')
app  = express.createServer()

app.listen 8080
app.use express.bodyParser()

app.post '/build', (req,res) ->
  script = fs.readFileSync(req.files.script.path).toString()
  message = { packaging: script, upload_uri: 'elsewhere', notify_subj: 'claw.builder.complete' }
  nats.request 'claw.builder.worker', JSON.stringify(message), (reply) ->
    console.log 'REPLY:'+reply
    sid = nats.subscribe 'claw.builder.complete', (finish_msg) ->
      nats.unsubscribe sid
      console.log 'FINISH:'+finish_msg
  res.send('ok')

