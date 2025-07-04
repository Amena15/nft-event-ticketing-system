const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log(`Deploying contracts with account: ${deployer.address}`);

    // Deploy NFTticketing (factory)
    const NFTticketing = await ethers.getContractFactory("NFTticketing");
    const nftTicketing = await NFTticketing.deploy();
    await nftTicketing.waitForDeployment();

    console.log(`✅ NFTticketing deployed to: ${nftTicketing.target}`);

    // No createEvent here — frontend will create events!
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Error in deploy.js:", error);
        process.exit(1);
    });
