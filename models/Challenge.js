module.exports = function(sequelize, DataTypes) {
	return sequelize.define('challenge', {
		title: DataTypes.STRING,
		category: DataTypes.STRING,
		points: { 
			type: DataTypes.INTEGER,
			defaultValue: 0
		},
		done: {
			type: DataTypes.BOOLEAN,
			defaultValue: false
		}
	});
};