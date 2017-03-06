express = require 'express'
https = require 'https'
httpProxy = require 'http-proxy'
process = require 'child_process'
fs = require 'fs'
mv = require 'mv'
cons = require 'consolidate'
WebSocketServer = require('ws').Server
models = require './models'
bcrypt = require 'bcrypt-nodejs'
util = require 'util'

# parse config file
config = null
console.log 'checking for config file'
if fs.existsSync 'config.json'
  console.log 'config file found, parsing...'
  try
    config = JSON.parse fs.readFileSync 'config.json'
  catch err
    console.log "error parsing config file: #{err}"
    return
  console.log "config loaded"
else
  console.log "config file not found"
  return

app = express()
app.engine 'html', cons.mustache
app.set 'view engine', 'html'
app.set 'views', 'web'
app.use express.bodyParser()
app.use express.cookieParser()

app.use '/js/', express.static 'web/js/'
app.use '/css/', express.static 'web/css/'
app.use '/img/', express.static 'web/img/'
app.use '/doc/', express.static 'web/doc/'

options =
  key: fs.readFileSync config.keyfile
  cert: fs.readFileSync config.certfile
server = https.createServer options, app
scoreboards = {2: ['test','test2']}


#Hack for having color. Pasted from etherpad source code.
colorPalette = ["#ffc7c7", "#fff1c7", "#e3ffc7", "#c7ffd5",
                "#c7ffff", "#c7d5ff", "#e3c7ff", "#ffc7f1",
                "#ff8f8f", "#ffe38f", "#c7ff8f", "#8fffab",
                "#8fffff", "#8fabff", "#c78fff", "#ff8fe3",
                "#d97979", "#d9c179", "#a9d979", "#79d991",
                "#79d9d9", "#7991d9", "#a979d9", "#d979c1",
                "#d9a9a9", "#d9cda9", "#c1d9a9", "#a9d9b5",
                "#a9d9d9", "#a9b5d9", "#c1a9d9", "#d9a9cd",
                "#4c9c82", "#12d1ad", "#2d8e80", "#7485c3",
                "#a091c7", "#3185ab", "#6818b4", "#e6e76d",
                "#a42c64", "#f386e5", "#4ecc0c", "#c0c236",
                "#693224", "#b5de6a", "#9b88fd", "#358f9b",
                "#496d2f", "#e267fe", "#d23056", "#1a1a64",
                "#5aa335", "#d722bb", "#86dc6c", "#b5a714",
                "#955b6a", "#9f2985", "#4b81c8", "#3d6a5b",
                "#434e16", "#d16084", "#af6a0e", "#8c8bd8"];

newRandomId = (length = 16) ->
    buf = new Buffer length
    fd = fs.openSync '/dev/urandom', 'r'
    fs.readSync fd, buf, 0, length, null
    buf.toString 'hex'


validateLogin = (user, pass, cb) ->
  models.User.findOne({ where: {name: user}}).then (row) ->
    if row is null then cb false
    else bcrypt.compare pass, row.pwhash, (err, res) ->
      if err or not res then cb false
      else
        sess = newRandomId()
        row.update({
          sessid: sess
        }).then( ->
          cb sess
        )

validateSession = (session, cb=->) ->
  models.User.findOne({ where: {sessid: session}}).then (user) ->
    if user is null then cb false
    else
      cb user


app.get '/', (req, res) ->
  validateSession req.cookies.ctfpad, (row) ->
    unless row then res.sendfile 'web/login.html'
    else
      user = {
        name: row.name,
        color: row.color,
        scope: row.scope,
        apikey: row.apikey,
        sessid: row.sessid
      }
      user.etherpad_port = config.etherpad_port
      models.Ctf.findAll().then (ctfs) ->
        user.all_ctfs = ctfs
        n = 0
        user.ctfs = []
        for i in ctfs
          if i.id is user.scope then user.current = i
          if n < 5 or i.id is user.scope
            user.ctfs.push(i)
          n++
        if user.current

          models.Ctf.findById(user.current.id, {
            include:
              [models.File, {
                model: models.Challenge,
                include: [models.File, models.User]
              }]
          }).then((ctf) ->
            user.current = ctf

            buf = {}

            for c in ctf.challenges
              if buf[c.category] is undefined then buf[c.category] = []
              c.impacts = []
              for name, value of config.impacts
                c.impacts.push {
                  name: name,
                  value: value,
                  selected: c.impact is name
                }
              if config.impacts[c.impact]
                c.impactvalue = config.impacts[c.impact]
              else
                c.impactvalue = 1

              buf[c.category].push c

            user.categories = []

            for k,v of buf
              user.categories.push {name:k, challenges:v}
            res.render 'index.html', user
          )
        else res.render 'index.html', user

app.post '/login', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    validateLogin req.body.name, req.body.password, (session) ->
      if session then res.cookie 'ctfpad', session
      res.redirect 303, '/'

app.get '/login', (req, res) -> res.redirect 303, '/'

app.post '/register', (req, res) ->
  if req.body.name and req.body.password1 and req.body.password2 and req.body.authkey
    if req.body.password1 == req.body.password2
      if req.body.authkey == config.authkey

        bcrypt.hash req.body.password1, bcrypt.genSaltSync(), null, (err, hash) ->
          if err then res.json {success: false, error: "#{err}"}
          models.User.create({
            name: req.body.name,
            pwhash: hash,
            color: colorPalette[Math.floor Math.random() * colorPalette.length]
          }).then( (user) ->
            res.json {success: true}
          ).catch (err) ->
            msg = ""
            for e in err.errors
              msg += "#{e.message}<br>"
            res.json {success: false, error: msg}


      else res.json {success: false, error: 'incorrect authkey'}
    else res.json {success: false, error: 'passwords do not match'}
  else res.json {success: false, error: 'incomplete request'}

app.get '/logout', (req, res) ->
  res.clearCookie 'ctfpad'
  # Clear etherpad token to avoid color problem
  res.clearCookie 'token'
  res.redirect 303, '/'

app.post '/changepassword', (req, res) ->
  validateSession req.header('x-session-id'), (ans) ->
    if ans
      if req.body.newpw and req.body.newpw2
        if req.body.newpw == req.body.newpw2
          bcrypt.hash req.body.password1, bcrypt.genSaltSync(), null, (err, hash) ->
            models.User.update(
              {pwhash: hash},
              {where: {sessid: req.header('x-session-id')}}
            ).then( (user) ->
              res.json {success: true}
            ).catch (err) ->
              msg = ""
              console.log err
              for e in err.errors
                msg += "#{e.message}<br>"
              res.json {success: false, error: msg}
        else res.json {success: false, error: 'inputs do not match'}
      else res.json {success: false, error: 'incomplete request'}
    else res.json {success: false, error: 'invalid session'}

app.post '/newapikey', (req, res) ->
  validateSession req.header('x-session-id'), (ans) ->
    apikey = newRandomId 32
    if ans
      ans.apikey = apikey
      ans.save().then( ->
        res.send apikey
      )
    else res.send 403

app.get '/scope/latest', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    if ans
      models.Ctf.max('id').then (id) ->
        ans.update({
          scope: id
        }).then ->
          res.redirect 303, '/'
    else
      res.redirect 303, '/'

app.get '/scope/:ctfid', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    if ans
      ans.update({
        scope: req.params.ctfid
      }).then ->
        res.redirect 303, '/'
    else
      res.redirect 303, '/'

app.get '/scoreboard', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    if ans and scoreboards[ans.scope]
      res.render 'scoreboard', scoreboards[ans.scope]
    else res.send ''

app.get '/files/:objtype/:objid', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    if ans
      objtype = ["ctf", "challenge"].indexOf(req.params.objtype)
      if objtype != -1
        objid = parseInt(req.params.objid)
        if isNaN objid
          res.send 400
          return
        filter = [{ctfId: objid}, {challengeId: objid}][objtype]

        models.File.findAll({where: filter, include: [models.User]}).then( (files) ->
          for file in files
            #file.uploaded = new Date(file.uploaded*1000).toISOString()
            if file.mimetype
              file.mimetype = file.mimetype.substr 0, file.mimetype.indexOf ';'
          res.render 'files.html', {files: files, objtype: req.params.objtype, objid: req.params.objid}
        )

      else res.send 404
    else res.send 403

app.get '/file/:fileid/:filename', (req, res) ->
  file = "#{__dirname}/uploads/#{req.params.fileid}"
  if /^[a-f0-9A-F]+$/.test(req.params.fileid) and fs.existsSync(file)
    models.File.findOne({where: {idText: req.params.fileid}}).then( (f) ->
      res.set 'Content-Type', f.mimetype
      res.sendfile file
    )
  else res.send 404

app.get '/delete_file/:fileid', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    if ans
      fid = req.params.fileid
      filepath = "#{__dirname}/uploads/#{fid}"
      if /^[a-f0-9A-F]+$/.test(fid) and fs.existsSync(filepath)
        models.File.findOne({where: {idText: fid}}).then( (file) ->
          if file isnt null
            fs.unlink filepath, (fserr) ->
              unless fserr
                res.json {success: true}

                type = null
                filter = null
                objid = null
                if file.ctfId
                  type = 0
                  filter = {ctfId: file.ctfId}
                  objid = file.ctfId
                else if file.challengeId
                  type = 1
                  filter = {challengeId: file.challengeId}
                  objid = file.challengeId
                else
                  file.destroy()
                  return
                file.destroy()

                models.File.count({where: filter}).then( (nb) ->
                  wss.broadcast JSON.stringify {type: 'fileupload', data: "#{["ctf", "challenge"][type]}#{objid}", filecount: nb}
                )


              else res.json {success: false, error: fserr}
          else
            res.json {success: false, error: "file not found"}
        )
      else res.json {success: false, error: "file not found on disk"}
    else res.send 403

upload = (user, objtype, objid, req, res) ->
  type = ["ctf", "challenge"].indexOf(objtype)
  if type != -1 and req.files.files
    mimetype = null
    process.execFile '/usr/bin/file', ['-bi', req.files.files.path], (err, stdout) ->
      mimetype = unless err then stdout.toString()

      file = {
        name: req.files.files.name,
        idText: newRandomId 32
        mimetype: mimetype
        userId: user.id
      }

      condition = {}

      if objtype is 'ctf'
        file.ctfId = objid
        condition = {
          ctfId: objid
        }
      else if objtype is 'challenge'
        file.challengeId = objid
        condition = {
          challengeId: objid
        }

      models.File.create(file).then( (f) ->
        mv req.files.files.path, "#{__dirname}/uploads/#{file.idText}", (err) ->
          if err then res.json {success: false, error: err}
          else
            res.json {success: true, id: file.idText}
            models.File.count({where: condition}).then( (nb) ->
              wss.broadcast JSON.stringify {type: 'fileupload', data: "#{objtype}#{objid}", filecount: nb}
            )

      ).catch( (err) ->
        msg = ""
        console.log err
        for e in err.errors
          msg += "#{e.message}<br>"
        res.json {success: false, error: msg}
      )
  else res.send 400

app.post '/upload/:objtype/:objid', (req, res) ->
  validateSession req.cookies.ctfpad, (user) ->
    if user
      upload user, req.params.objtype, req.params.objid, req, res
    else res.send 403

#api = require './api.coffee'
#api.init app, db, upload, ''

## PROXY INIT
proxyTarget = {host: 'localhost', port: config.etherpad_internal_port}
proxy = httpProxy.createProxyServer {target: proxyTarget}
proxy.on 'error', (err, req, res) ->
  if err then console.log err
  try
    res.send 500
  catch e then return

proxyServer = https.createServer options, (req, res) ->
  if req.headers.cookie
    sessid = req.headers.cookie.substr req.headers.cookie.indexOf('ctfpad=')+7, 32
    validateSession sessid, (ans) ->
      if ans
        proxy.web req, res
      else
        res.writeHead 403
        res.end()
  else
    res.writeHead 403
    res.end()

###proxyServer.on 'upgrade', (req, socket, head) -> ## USELESS SOMEHOW???
  console.log "UPGRADE UPGRADE UPGRADE"
  sessid = req.headers.cookie.substr req.headers.cookie.indexOf('ctfpad=')+7, 32
  validateSession sessid, (ans) ->
    if ans then proxy.ws req, socket, head else res.send 403###

## START ETHERPAD
etherpad = process.exec "cd #{__dirname}/etherpad-lite && node ./src/node/server.js"

etherpad.stdout.on 'data', (line) ->
  console.log "[etherpad] #{line.toString 'utf8', 0, line.length-1}"
etherpad.stderr.on 'data', (line) ->
  console.log "[etherpad] #{line.toString 'utf8', 0, line.length-1}"

wss = new WebSocketServer {server:server}
wss.broadcast = (msg, exclude, scope=null) ->
  for c in this.clients
    unless c.authenticated then continue
    if c isnt exclude and (scope is null or scope is c.authenticated.scope)
      try
        c.send msg
      catch e
        console.log e
#api.broadcast = (obj, scope) -> wss.broadcast JSON.stringify(obj), null, scope
wss.getClients = -> this.clients
wss.on 'connection', (sock) ->
  sock.on 'close', ->
    if sock.authenticated
      wss.broadcast JSON.stringify {type: 'logout', data: sock.authenticated.name}
      sock.authenticated.challengeId = null
      sock.authenticated.save()
  sock.on 'message', (message) ->
    msg = null
    try msg = JSON.parse(message) catch e then return
    unless sock.authenticated
      if typeof msg is 'string'
        validateSession msg, (ans) ->
          if ans
            sock.authenticated = ans
            # send assignments on auth
            if ans.scope
              models.Ctf.findById(ans.scope, {
                include:
                  [{
                    model: models.Chat,
                    include: [models.User]
                  },
                  {
                    model: models.Challenge,
                    include: [{
                      model: models.User,
                      as: 'assigneds'
                    }]
                  }]
              }).then((ctf) ->
                if ctf is null then return

                chatMessages = []
                for msg in ctf.chats
                  chatMessages.push {
                    name: msg.user.name,
                    message: msg.message,
                    color: msg.user.color,
                    time: msg.createdAt
                  }
                sock.send JSON.stringify {type: 'chat', data: chatMessages}

                for chal in ctf.challenges
                  for user in chal.assigneds
                    sock.send JSON.stringify {
                      type: 'assign',
                      subject: chal.id,
                      data: [{name: user.name}, true]}
              )

            # notify all users about new authentication and notify new socket about other users
            wss.broadcast JSON.stringify {type: 'login', data: ans.name}
            for s in wss.getClients()
              if s.authenticated and s.authenticated.name isnt ans.name
                sock.send JSON.stringify {type: 'login', data: s.authenticated.name}
    else
      if msg.type and msg.type is 'done'
        clean = {data: Boolean(msg.data), subject: msg.subject, type: 'done'}
        wss.broadcast JSON.stringify(clean), null
        models.Challenge.update(
          {done: Boolean(msg.data)},
          {where: {id: msg.subject}}
        )

      else if msg.type and msg.type is 'assign'
        models.Assigned.findCreateFind({
          where: {
            challengeId: msg.subject,
            userId: sock.authenticated.id
          }
        }).spread( (assigned, created) ->
          if not created
            assigned.destroy()
          data = [{name:sock.authenticated.name}, created]
          wss.broadcast JSON.stringify({type: 'assign', data: data, subject: msg.subject}), null
        ).catch( (err) ->
          console.log err
        )

      else if msg.type and msg.type is 'newctf'
        challenges = []
        for c in msg.data.challenges
          challenges.push {
            title: c.title,
            category: c.category,
            points: c.points,
            impact: config.defaultImpact,
            done: false
          }
        models.Ctf.create({
          name: msg.data.title,
          challenges: challenges
        }, {
          include: [models.Challenge]
        })

      else if msg.type and msg.type is 'modifyctf'
        for c in msg.data.challenges
          if c.id
            models.Challenge.update({
              title: c.title,
              category: c.category,
              points: c.points
            }, {
              where: {
                id: c.id
              }
            })
          else
            models.Challenge.create({
              title: c.title,
              category: c.category,
              points: c.points,
              ctfId: sock.authenticated.scope,
              impact: config.defaultImpact
            })
        for s in wss.clients
          if s.authenticated and s.authenticated.scope is msg.data.ctf
            s.send JSON.stringify {type: 'ctfmodification'}

      else if msg.type and msg.type is 'setactive'
        if msg.subject
          models.Challenge.findById(msg.subject).then (chal) ->
            if chal is null then return
            sock.authenticated.challengeId = chal.id
            sock.authenticated.save()
            wss.broadcast JSON.stringify {
              type: 'setactive',
              challenge: chal.id,
              name: sock.authenticated.name,
              color: sock.authenticated.color
            }

      else if msg.type and msg.type is 'chat'
        # tode block xss
        if msg.message and typeof msg.message is 'string'
          time = new Date().toISOString();

          wss.broadcast JSON.stringify {type: 'chat', data: [{
            name: sock.authenticated.name,
            message: msg.message,
            color: sock.authenticated.color,
            time: time
          }]}, sock.authenticated.scope

          models.Chat.create {
            message: msg.message
            userId: sock.authenticated.id,
            ctfId: sock.authenticated.scope
          }
      else if msg.type and msg.type is 'setimpact'
        if msg.id and msg.impact and config.impacts[msg.impact]
          models.Challenge.update({
            impact: msg.impact
          },{
            where: {id: msg.id}
          })
          wss.broadcast JSON.stringify {
            type: 'setimpact',
            id: msg.id,
            value: config.impacts[msg.impact],
            name: msg.impact
          }

      else console.log msg

server.listen config.port
proxyServer.listen config.etherpad_port
console.log "listening on port #{config.port} and #{config.etherpad_port}"

filetype = (path,cb = ->) ->
  p = process.spawn 'file', ['-b', path]
  p.stdout.on 'data', (output) ->
    cb output.toString().substr 0,output.length-1
