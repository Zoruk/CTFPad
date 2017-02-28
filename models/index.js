var Sequelize = require('sequelize');
var fs = require('fs');

var config = null;

console.log('checking for db config file');

if (fs.existsSync('dbconfig.json')) {
  console.log('db config file found, parsing...');
  try {
    config = JSON.parse(fs.readFileSync('dbconfig.json'));
  } catch (err) {
    console.log("error parsing dbconfig file: " + err);
    return;
  }
  console.log("config loaded");
} else {
  console.log("config file not found");
  return;
}

// initialize database connection
var sequelize = null;

if (config.engine === 'sqlite') {
  sequelize = new Sequelize('database', 'username', 'password', {
    dialect: config.engine,
    storage: config.file,
    logging: console.log
  });
} else {
  sequelize = new Sequelize(config.db, config.username, config.password, {
    dialect: config.engine
  });
}

models = [
  'Ctf', 
  'Challenge', 
  'User', 
  'File', 
  'Chat',
  'Assigned'
];

models.forEach(function(model) {
  console.log(model)
  module.exports[model] = sequelize.import(__dirname + '/' + model);
});

// describe relationships
(function(m) {
  m.Ctf.hasMany(m.Challenge);
  m.Ctf.hasMany(m.File);
  m.Ctf.hasMany(m.Chat);

  m.Challenge.belongsTo(m.Ctf);
  m.Challenge.hasMany(m.User); /* work on */
  m.Challenge.hasMany(m.File);
  m.Challenge.belongsToMany(m.User, {through: m.Assigned, as: 'assigneds'});

  m.User.belongsToMany(m.Challenge, {through: m.Assigned, as: 'assigneds'});
  m.User.hasMany(m.Chat);
  m.User.hasMany(m.File);

  m.Chat.belongsTo(m.Ctf);
  m.Chat.belongsTo(m.User);

  m.File.belongsTo(m.Ctf);
  m.File.belongsTo(m.Challenge);
  m.File.belongsTo(m.User);
})(module.exports);

sequelize.sync({ logging: console.log }).then(function () {
  sequelize.showAllSchemas();
});
// export connection
module.exports.sequelize = sequelize;