import * as hre from 'hardhat';
import { MocERC20 } from '../types/ethers-contracts/MocERC20';
import { MocERC20__factory } from '../types/ethers-contracts/factories/MocERC20__factory';
import address from '../address';

require("dotenv").config();

const { ethers } = hre;

const sleep = (milliseconds, msg='') => {
    console.log(`Wait ${milliseconds} ms... (${msg})`);
    const date = Date.now();
    let currentDate = null;
    do {
      currentDate = Date.now();
    } while (currentDate - date < milliseconds);
}

const toEther = (val) => {
    return ethers.utils.formatEther(val);
}

const parseEther = (val, unit = 18) => {
    return ethers.utils.parseUnits(val, unit);
}

async function deploy() {
    console.log((new Date()).toLocaleString());
    
    const [deployer] = await ethers.getSigners();
    
    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const beforeBalance = await deployer.getBalance();
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const mainnet = process.env.NETWORK == "mainnet" ? true : false;
    const url = mainnet ? process.env.URL_MAIN : process.env.URL_TEST;
    const curBlock = await ethers.getDefaultProvider(url).getBlockNumber();

    const factory: MocERC20__factory = new MocERC20__factory(deployer);
    let idoToken: MocERC20 = factory.attach(address.testnet.idoToken).connect(deployer);
    if ("redeploy" && true) {
        idoToken = await factory.deploy("LaunchpadToken", "IDOTOKEN", 18);
        
    }
    console.log(`Deployed Launchpad Token... (${idoToken.address})`);

    let presale: MocERC20 = factory.attach(address.testnet.presaleToken).connect(deployer);
    if ("redeploy" && true) {
        idoToken = await factory.deploy("PresaleToken", "PRETOKEN", 18);
        
    }
    console.log(`Deployed Presale Token... (${idoToken.address})`);

    let investToken: MocERC20 = factory.attach(address.testnet.investToken).connect(deployer);
    if ("redeploy" && true) {
        idoToken = await factory.deploy("InvestToken", "INVTOKEN", 18);
        
    }
    console.log(`Deployed Invest Token... (${idoToken.address})`);


    const afterBalance = await deployer.getBalance();
    console.log(
        "Deployed cost:",
         (beforeBalance.sub(afterBalance)).toString()
    );
}

deploy()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    })