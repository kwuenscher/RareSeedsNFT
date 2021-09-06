const MyContract = artifacts.require("RareSeedsMarket");

module.exports = async function (deployer, network, accounts) {
  // deployment steps
  await deployer.deploy(MyContract);
};