module.exports = function(sequelize, DataTypes) {
	return sequelize.define('challenge', {
		title: DataTypes.STRING,
		category: DataTypes.STRING,
		points: {
			type: DataTypes.INTEGER,
			defaultValue: 0
		},
		impact: {
			type: DataTypes.STRING
		},
		done: {
			type: DataTypes.BOOLEAN,
			defaultValue: false
		}
	});
};