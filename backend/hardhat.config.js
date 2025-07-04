require("@nomicfoundation/hardhat-toolbox");

module.exports = {
    solidity: {
        version: "0.8.21", // or your version
        settings: {
            optimizer: {
                enabled: true,
                runs: 200, // lower runs → smaller size
            },
        },
    },
};


