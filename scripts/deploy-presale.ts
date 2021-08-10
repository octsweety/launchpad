import * as hre from 'hardhat';
import { MocERC20 } from '../types/ethers-contracts/MocERC20';
import { MocERC20__factory } from '../types/ethers-contracts/factories/MocERC20__factory';
import { StakePool } from '../types/ethers-contracts/StakePool';
import { StakePool__factory } from '../types/ethers-contracts/factories/StakePool__factory';
import { Presale } from '../types/ethers-contracts/Presale';
import { Presale__factory } from '../types/ethers-contracts/factories/Presale__factory';
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

const toHex = (val) => {
    return ethers.utils.hexZeroPad(ethers.utils.hexlify(val), 32);
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
    const idoTokenAddress = mainnet ? address.mainnet.idoToken : address.testnet.idoToken;
    const presaleTokenAddress = mainnet ? address.mainnet.idoToken : address.testnet.presaleToken;
    const poolAddress = mainnet ? address.mainnet.stakePool : address.testnet.stakePool;
    const lockerAddress = mainnet ? address.mainnet.locker : address.testnet.locker;
    const bnbPresaleAddress = mainnet ? address.mainnet.presales.bnbPresale : address.testnet.presales.bnbPresale;
    const tokenPresaleAddress = mainnet ? address.mainnet.presales.tokenPresale : address.testnet.presales.tokenPresale;
    const routerAddress = mainnet ? address.mainnet.uniswapRouter : address.testnet.uniswapRouter;
    const curTime = Math.floor(Date.now() / 1000);

    const presaleFactory: Presale__factory = new Presale__factory(deployer);
    let bnbPresale: Presale = presaleFactory.attach(bnbPresaleAddress).connect(deployer);
    if ("redeploy" && false) {
        bnbPresale = await presaleFactory.deploy(
            presaleTokenAddress,
            address.mainnet.bnb,
            curTime,                        // Just start
            600,                            // 10 mins duration
            parseEther('5000'),             // 5kBNB hardCap
            parseEther('3000'),             // 3k softCap
            poolAddress
        );
    }
    console.log(`Deployed BNB Presale... (${bnbPresale.address})`);
    // await bnbPresale.setUniswapRouter(routerAddress);

    let tokenPresale: Presale = presaleFactory.attach(tokenPresaleAddress).connect(deployer);
    if ("redeploy" && true) {
        tokenPresale = await presaleFactory.deploy(
            presaleTokenAddress,
            address.testnet.investToken,
            curTime,                        // Just start
            600,                            // 10 mins duration
            parseEther('5000'),             // 5kBNB hardCap
            parseEther('3000'),             // 3k softCap
            poolAddress
        );
    }
    console.log(`Deployed Token Presale... (${tokenPresale.address})`);
    // await tokenPresale.setUniswapRouter(routerAddress);

    console.log(
        presaleTokenAddress,
        address.testnet.investToken,
        curTime,                        // Just start
        600,                            // 10 mins duration
        parseEther('5000').toString(),             // 5kBNB hardCap
        parseEther('3000').toString(),             // 3k softCap
        poolAddress
    );

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