#database.coffee
bcrypt = require 'bcrypt-nodejs'
sqlite3 = require 'sqlite3'
fs = require 'fs'

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


# SQLITE DB
stmts = {}
sql = new sqlite3.Database 'ctfpad.sqlite', ->
  #stmts.getUser = sql.prepare 'SELECT name,scope,apikey FROM user WHERE sessid = ?'
  stmts.getUser = sql.prepare 'SELECT name,color,scope,apikey FROM user WHERE sessid = ?'
  stmts.getUserByApiKey = sql.prepare 'SELECT name,scope FROM user WHERE apikey = ? AND apikey NOT NULL'
  #stmts.addUser = sql.prepare 'INSERT INTO user (name,pwhash) VALUES (?,?)'
  stmts.addUser = sql.prepare 'INSERT INTO user (name,pwhash, color) VALUES (?,?,?)'
  stmts.getUserPW = sql.prepare 'SELECT pwhash FROM user WHERE name = ?'
  stmts.insertSession = sql.prepare 'UPDATE user SET sessid = ? WHERE name = ?'
  stmts.voidSession = sql.prepare 'UPDATE user SET sessid = NULL WHERE sessid = ?'
  stmts.getChallenges = sql.prepare 'SELECT id,title,category,points,done FROM challenge WHERE ctf = ? ORDER BY category,points,id'
  stmts.getChallenge = sql.prepare 'SELECT * FROM challenge WHERE id = ?' 
  stmts.addChallenge = sql.prepare 'INSERT INTO challenge (ctf, title, category, points) VALUES (?,?,?,?)'
  stmts.modifyChallenge = sql.prepare 'UPDATE challenge SET title = ?, category = ?, points = ? WHERE id = ?'
  stmts.setDone = sql.prepare 'UPDATE challenge SET done = ? WHERE id = ?'
  stmts.getCTFs = sql.prepare 'SELECT id,name FROM ctf ORDER BY id DESC'
  stmts.addCTF = sql.prepare 'INSERT INTO ctf (name) VALUES (?)'
  stmts.changeScope = sql.prepare 'UPDATE user SET scope = ? WHERE name = ?'
  stmts.isAssigned = sql.prepare 'SELECT COUNT(*) AS assigned FROM assigned WHERE user = ? AND challenge = ?'
  stmts.assign = sql.prepare 'INSERT INTO assigned VALUES (?,?)'
  stmts.unassign = sql.prepare 'DELETE FROM assigned WHERE user = ? AND challenge = ?'
  stmts.changePassword = sql.prepare 'UPDATE user SET pwhash = ? WHERE sessid = ?'
  stmts.getApiKeyFor = sql.prepare 'SELECT apikey FROM user WHERE sessid = ?'
  stmts.setApiKeyFor = sql.prepare 'UPDATE user SET apikey = ? WHERE sessid = ?'
  stmts.listAssignments = sql.prepare 'SELECT assigned.challenge,assigned.user FROM assigned JOIN challenge ON assigned.challenge = challenge.id JOIN user ON assigned.user = user.name WHERE challenge.ctf = ?'
  stmts.listAssignmentsForChallenge = sql.prepare 'SELECT user FROM assigned WHERE challenge = ?'
  stmts.getFiles = sql.prepare 'SELECT id,name,user,uploaded,mimetype FROM file WHERE CASE ? WHEN 1 THEN ctf WHEN 2 THEN challenge END = ?'
  stmts.addFile = sql.prepare 'INSERT INTO file (id, name, user, ctf, challenge, uploaded, mimetype) VALUES (?,?,?,?,?,?,?)'
  stmts.findFile = sql.prepare 'SELECT ctf,challenge FROM file WHERE id = ?'
  stmts.fileMimetype = sql.prepare 'SELECT mimetype FROM file WHERE id = ?'
  stmts.deleteFile = sql.prepare 'DELETE FROM file WHERE id = ?'
  stmts.getLatestCtfId = sql.prepare 'SELECT id FROM ctf ORDER BY id DESC LIMIT 1'

  # Zoruk
  # Active challenges
  stmts.setActiveChallenge = sql.prepare 'UPDATE user SET challenge = ? WHERE name = ?'
  stmts.getActiveUserByChal = sql.prepare 'SELECT name, color FROM user WHERE challenge = ?'
  # Chat
  stmts.getChatMessages = sql.prepare 'SELECT chat.user,chat.message,user.color,chat.time FROM chat JOIN user ON chat.user=user.name WHERE chat.ctf = ?'
  stmts.addChatMessage = sql.prepare 'INSERT INTO chat (user, message, time, ctf) VALUES (?,?,?,?)'

#
# EXPORTS
#
exports.validateSession = (sess, cb = ->) ->
  stmts.getUser.get [sess], H cb

exports.checkPassword = (name, pw, cb = ->) ->
  stmts.getUserPW.get [name], H (row) ->
    unless row then cb false
    else bcrypt.compare pw, row.pwhash, (err, res) ->
      if err or not res then cb false
      else
        sess = newRandomId()
        cb sess
        stmts.insertSession.run [sess, name]

exports.validateApiKey = (apikey, cb) ->
  stmts.getUserByApiKey.get [apikey], H cb
  stmts.getUserByApiKey.reset()

exports.voidSession = (sessionId) -> stmts.voidSession.run [sessionId]

exports.setChallengeDone = (chalId, done) ->
  stmts.setDone.run [(if done then 1 else 0), chalId]

exports.getChallenges = (ctfId, cb = ->) ->
  stmts.getChallenges.all [ctfId], H cb

exports.getChallenge = (challengeId, cb = ->) ->
  stmts.getChallenge.get [challengeId], H cb
  stmts.getChallenge.reset()

exports.addChallenge = (ctfId, title, category, points, cb = ->) ->
  stmts.addChallenge.run [ctfId, title, category, points], (err) ->
    cb(this.lastID)

exports.modifyChallenge = (chalId, title, category, points) ->
  stmts.modifyChallenge.run [title, category, points, chalId]

exports.getCTFs = (cb = ->) ->
  stmts.getCTFs.all [], H cb

exports.addCTF = (title, cb = ->) ->
  stmts.addCTF.run [title], (err) ->
    cb(this.lastID)

exports.changeScope = (user, ctfid) ->
  stmts.changeScope.run [ctfid, user]

exports.toggleAssign = (user, chalid, cb = ->) ->
  stmts.isAssigned.get [user, chalid], H (ans) ->
    if ans.assigned
      exports.unassign user, chalid
      cb false
    else
      exports.assign user, chalid
      cb true
  stmts.isAssigned.reset()

exports.assign = (user, chalid, cb = ->) ->
  stmts.assign.run [user,chalid], cb

exports.unassign = (user, chalid, cb = ->) ->
  stmts.unassign.run [user,chalid], cb

exports.listAssignments = (ctfid, cb = ->) ->
  stmts.listAssignments.all [ctfid], H cb
  stmts.listAssignments.reset()

exports.listAssignmentsForChallenge = (chalId, cb = ->) ->
  stmts.listAssignmentsForChallenge.all [chalId], H cb
  stmts.listAssignmentsForChallenge.reset()

exports.changePassword = (sessid, newpw, cb = ->) ->
  bcrypt.hash newpw, bcrypt.genSaltSync(), null, (err, hash) ->
    if err then cb err
    else
      stmts.changePassword.run [hash, sessid]
      cb false

exports.getApiKeyFor = (sessid, cb = ->) ->
  stmts.getApiKeyFor.get [sessid], H (row) ->
    cb if row then row.apikey else ''
  stmts.getApiKeyFor.reset()

exports.newApiKeyFor = (sessid, cb = ->) ->
  apikey = newRandomId 32
  stmts.setApiKeyFor.run [apikey, sessid]
  setImmediate cb, apikey

exports.addUser = (name, pw, cb = ->) ->
  bcrypt.hash pw, bcrypt.genSaltSync(), null, (err, hash) ->
    if err then cb err
    else
      color = colorPalette[Math.floor Math.random() * colorPalette.length]
      stmts.addUser.run [name, hash, color], (err, ans) ->
        if err
          cb err
        else
          cb false

exports.getCTFFiles = (id, cb = ->) ->
  stmts.getFiles.all [1, id], H cb
  stmts.getFiles.reset()

exports.getChallengeFiles = (id, cb = ->) ->
  stmts.getFiles.all [2, id], H cb
  stmts.getFiles.reset()

exports.addChallengeFile = (chal, name, user, mimetype, cb = ->) ->
  id = newRandomId(32)
  stmts.addFile.run [id, name, user, null, chal, new Date().getTime()/1000, mimetype], (err, ans) ->
    cb err, id

exports.addCTFFile = (ctf, name, user, mimetype, cb = ->) ->
  id = newRandomId(32)
  stmts.addFile.run [id, name, user, ctf, null, new Date().getTime()/1000, mimetype], (err, ans) ->
    cb err, id

exports.mimetypeForFile = (id, cb = ->) ->
  stmts.fileMimetype.get [id], H ({mimetype: mimetype}) -> cb(mimetype)

exports.deleteFile = (fileid, cb = ->) ->
  stmts.findFile.get [fileid], H ({ctf:ctf, challenge:challenge}) ->
    stmts.deleteFile.run [fileid], (err) ->
      cb err, (if ctf then 0 else 1), (if ctf then ctf else challenge)

exports.getLatestCtfId = (cb = ->) ->
  stmts.getLatestCtfId.get H (row) ->
    stmts.getLatestCtfId.reset ->
      cb(if row isnt undefined then row.id else -1)

# Active challenge
exports.setActiveChallenge = (user, challenge, cb = ->) ->
  stmts.setActiveChallenge.run [challenge, user], cb

exports.getActiveUserByChal = (challenge, cb = ->) ->
  stmts.getActiveUserByChal.all [challenge], H cb


# Chat
exports.getChatMessages = (ctfid, cb = ->) ->
  stmts.getChatMessages.all [ctfid], H cb

exports.addChatMessage = (user, message, time, ctf, cb = ->) ->
  stmts.addChatMessage.run [user, message, time, ctf], (err) ->
    cb(this.lastID)

#
# UTIL
#
H = (cb=->) ->
  return (err, ans) ->
    if err then console.log err
    else cb ans

newRandomId = (length = 16) ->
    buf = new Buffer length
    fd = fs.openSync '/dev/urandom', 'r'
    fs.readSync fd, buf, 0, length, null
    buf.toString 'hex'

