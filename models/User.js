module.exports = function(sequelize, DataTypes) {
	return sequelize.define('user', {
		name: { 
			type: DataTypes.STRING,
			unique: true,
			validate: {
				isAlphanumeric: {
					args: true,
					msg: "Username can only contain regulan letters"
				},
				len: {
					args: [3, 10],
					msg: "Username length must be between 3 and 10"
				}
			}
		},
		pwhash: DataTypes.STRING,
		sessid: DataTypes.STRING,
		scope: { 
			type: DataTypes.INTEGER,
			defaultValue: 0
		},
		apikey: {
			type: DataTypes.STRING,
			allowNull: true
		},
		color: DataTypes.STRING
	});
};