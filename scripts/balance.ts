import * as hre from 'hardhat';
import { GYA } from '../types/ethers-contracts/GYA';
import { GYA__factory } from '../types/ethers-contracts/factories/GYA__factory';
const { ethers } = hre;

require("dotenv").config();

const toEther = (val) => {
    return ethers.utils.formatEther(val);
}

async function deploy() {
    console.log((new Date()).toLocaleString());

    const [deployer] = await ethers.getSigners();
    
    const mainnet = process.env.NETWORK == "mainnet" ? true : false;
    const gyaAddress = mainnet ? process.env.GYA_MAIN : process.env.GYA_TEST
    const url = mainnet ? process.env.URL_MAIN : process.env.URL_TEST;

    const gyaFactory: GYA__factory = new GYA__factory(deployer);
    const gya: GYA = await gyaFactory.attach(gyaAddress).connect(deployer);
    
    console.log("Account: ", deployer.address);
    const balance = await deployer.getBalance();
    console.log("Account balance(wei): ", balance.toString());
    console.log("Account balance(ether): ", toEther(balance));
    console.log("GYA Balance: ", toEther(await gya.balanceOf('0xC627D743B1BfF30f853AE218396e6d47a4f34ceA')));
    // console.log("GYA Balance: ", toEther(await gya.balanceOf(deployer.address)));

    const block = await ethers.getDefaultProvider(url).getBlockNumber();
    console.log("Block number: ", block);
}

deploy()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    })