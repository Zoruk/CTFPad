module.exports = function(sequelize, DataTypes) {
	return sequelize.define('ctf', {
		name: DataTypes.STRING
	});
};