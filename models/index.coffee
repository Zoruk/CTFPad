Sequelize = require 'sequelize'
fs = require 'fs'

# parse db config file
config = null
console.log 'checking for db config file'
if fs.existsSync 'dbconfig.json'
  console.log 'db config file found, parsing...'
  try
    config = JSON.parse fs.readFileSync 'dbconfig.json'
  catch err
    console.log "error parsing dbconfig file: #{err}"
    return
  console.log "config loaded"
else
  console.log "config file not found"
  return


sequelize = null

if config.engine is 'sqlite'
  sequelize = new Sequelize 'database', 'username', 'password', {
    dialect: config.engine,
    storage: config.file
  }
else
  sequelize = new Sequelize config.db, config.username, config.password, {
    dialect: config.engine
  }

models = [
  'Ctf',
  'Challeenge',
  'User',
  'File',
  'ChatS'
]

for m in models
	module.exports[m] = sequelize.import("#{__dirname}/#{m}")
