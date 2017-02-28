module.exports = function(sequelize, DataTypes) {
	return sequelize.define('file', {
		name: DataTypes.STRING,
		idText: {
			type: DataTypes.STRING,
			unique: true
		},
		mimetype: {
			type: DataTypes.STRING,
			defaultValue: 'application/octet-stream; charset=binary'
		}
	});
};