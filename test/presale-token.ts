import { expect, use } from 'chai';
import { solidity } from 'ethereum-waffle';

import * as hre from 'hardhat';
import { StakePool } from '../types/ethers-contracts/StakePool';
import { StakePool__factory } from '../types/ethers-contracts/factories/StakePool__factory';
import { Locker } from '../types/ethers-contracts/Locker';
import { Locker__factory } from '../types/ethers-contracts/factories/Locker__factory';
import { Presale } from '../types/ethers-contracts/Presale';
import { Presale__factory } from '../types/ethers-contracts/factories/Presale__factory';
import { MocERC20 } from '../types/ethers-contracts/MocERC20';
import { MocERC20__factory } from '../types/ethers-contracts/factories/MocERC20__factory';
import address from '../address';
require("dotenv").config();

const { ethers } = hre;

use(solidity);

const parseEther = (val, unit = 18) => {
    return ethers.utils.parseUnits(val, unit);
}

const toEther = (val, unit = 18) => {
    return ethers.utils.formatUnits(val, unit);
}

describe('Testing Presale with Token...', () => {
    let deployer;
    let account1;
    let account2;
    let beforeBalance;
    let pool: StakePool;
    let presale: Presale;
    let locker: Locker;
    let presaleToken: MocERC20;
    let idoToken: MocERC20;
    let investToken: MocERC20;
    let curBlock;
    let curTimestamp;
    let lpSupply;
    const presaleDecimals = 9;
    const investDecimals = 18;


    before(async () => {
        let accounts  = await ethers.getSigners();

        deployer = accounts[0];
        account1 = accounts[1];
        account2 = accounts[2];
        console.log(`Deployer => ${deployer.address}`);
        beforeBalance = await deployer.getBalance();
        console.log("Deployer before balance => ", toEther(beforeBalance));
        
        const erc20Factory = new MocERC20__factory(deployer);
        presaleToken = await erc20Factory.deploy("Presale Token", "PRETOKEN", presaleDecimals);
        console.log("PresaleToken address => ", presaleToken.address);
        curBlock = await presaleToken.getBlock();
        curTimestamp = await presaleToken.getTimestamp();

        idoToken = await erc20Factory.deploy("Launchpad Token", "IDOTOKEN",18);
        console.log("LaunchpadToken address => ", idoToken.address);

        investToken = await erc20Factory.deploy("Invest Token", "INVTOKEN", investDecimals);
        console.log("InvestToken address => ", investToken.address);

        const poolFactory = new StakePool__factory(deployer);
        pool = await poolFactory.deploy(idoToken.address);
        console.log("StakePool address => ", pool.address);

        const lockFactory = new Locker__factory(deployer);
        locker = await lockFactory.deploy();
        console.log("Locker address => ", locker.address);

        const presaleFactory = new Presale__factory(deployer);
        presale = await presaleFactory.deploy(
            presaleToken.address,
            investToken.address,
            curTimestamp+5,                 // Just start
            10,                             // 10 sec duration
            parseEther('5000', investDecimals),             // 5kBNB hardCap
            parseEther('3000', investDecimals),             // 3k softCap
            parseEther('0.1'),              // 0.1BNB listingPrice
            5000,                           // 50% liquidity
            locker.address,
            0,                            // 0 mins locking
            pool.address,
            account2.address                // Keeper
        );
        console.log("Presale address => ", presale.address);

        await presale.setUniswapRouter(address.testnet.uniswapRouter);
    });

    after(async () => {
        [ deployer ] = await ethers.getSigners();
        const afterBalance = await deployer.getBalance();
        console.log('');
        console.log("Deployer after balance => ", ethers.utils.formatEther(afterBalance));
        const cost = beforeBalance.sub(afterBalance);
        console.log("Test Cost: ", ethers.utils.formatEther(cost));
    });

    it('Distribute 200k assets to each accounts', async () => {
        await presaleToken.transfer(account1.address, parseEther('200000', presaleDecimals));
        await presaleToken.transfer(account2.address, parseEther('200000', presaleDecimals));

        await presaleToken.approve(presale.address, parseEther('99999999999999', presaleDecimals));
        await presaleToken.connect(account1).approve(presale.address, parseEther('99999999999999', presaleDecimals));
        await presaleToken.connect(account2).approve(presale.address, parseEther('99999999999999', presaleDecimals));

        await idoToken.transfer(account1.address, parseEther('200000'));
        await idoToken.transfer(account2.address, parseEther('200000'));

        await idoToken.approve(pool.address, parseEther('99999999999999'));
        await idoToken.connect(account1).approve(pool.address, parseEther('99999999999999'));
        await idoToken.connect(account2).approve(pool.address, parseEther('99999999999999'));

        await investToken.transfer(account1.address, parseEther('200000', investDecimals));
        await investToken.transfer(account2.address, parseEther('200000', investDecimals));

        await investToken.approve(presale.address, parseEther('99999999999999', investDecimals));
        await investToken.connect(account1).approve(presale.address, parseEther('99999999999999', investDecimals));
        await investToken.connect(account2).approve(presale.address, parseEther('99999999999999', investDecimals));
    });

    it('Stake', async () => {
        await pool.setLockDuration(0, 0);
        await pool.setLockDuration(1, 0);
        await pool.setLockDuration(2, 0);
        await pool.setLockDuration(3, 0);
        await pool.setLockDuration(4, 0);

        const pool0 = await pool.poolInfo(0);
        const pool1 = await pool.poolInfo(1);

        await pool.connect(account1).stake(0, pool0.unitAmount);
        await pool.connect(account1).stake(1, pool1.unitAmount);
        await pool.connect(account2).stake(0, pool0.unitAmount.mul(2));

        const totalAvailable = await pool.totalAvailable(0);

        expect(totalAvailable).eq(pool0.unitAmount.mul(3));
    });

    it('Supply 2 times', async () => {
        const totalSupply = await presale.totalSupply();

        await presale.deposit(parseEther('50000', presaleDecimals));

        expect(await presale.totalSupply()).eq(totalSupply.add(parseEther('50000', presaleDecimals)));

        await presale.deposit(parseEther('50000', presaleDecimals));

        expect(await presale.totalSupply()).eq(totalSupply.add(parseEther('100000', presaleDecimals)));
        console.log("Total Supply: ", toEther(await presale.totalSupply(), presaleDecimals));
    });

    it('Invest from account1', async () => {
        await presale.updateTiers();
        // Force start...
        const curTime = await presale.getTimestamp();
        await presale.setStartTime(curTime.sub(10), 20)

        const pool0 = await pool.poolInfo(0);
        const pool1 = await pool.poolInfo(1);
        const pool4 = await pool.poolInfo(4);
        const totalAlloc = await presale.totalAllocation();
        console.log(`totalAlloc: ${totalAlloc.toString()}, alloc0: ${pool0.allocPoint.toString()}`);

        const hardCap = await presale.hardCap();
        const cap0 = hardCap.mul(pool0.allocPoint).div(totalAlloc);
        const cap1 = hardCap.mul(pool1.allocPoint).div(totalAlloc);
        const cap4 = hardCap.mul(pool4.allocPoint).div(totalAlloc);
        const available0 = await pool.totalAvailable(0);
        const available1 = await pool.totalAvailable(1);
        const balance0 = (await pool.balanceOf(0, account1.address)).unlocked;
        const balance1 = (await pool.balanceOf(1, account1.address)).unlocked;
        const calcInvestable = cap0.mul(balance0).div(available0).add(cap1.mul(balance1).div(available1));
        console.log(`alloc0Cap: ${toEther(cap0, investDecimals)}, alloc1Cap: ${toEther(cap1, investDecimals)}, alloc4Cap: ${toEther(cap4, investDecimals)}`);
        console.log("Calculated Investable: ", toEther(calcInvestable, investDecimals));
        
        const totalInvestable = await presale.totalInvestable(account1.address);
        expect(calcInvestable).eq(totalInvestable);

        let investable = await presale.investable(account1.address);
        console.log(`beforeInvest => totalInvestable: ${toEther(totalInvestable, investDecimals)}, investable: ${toEther(investable, investDecimals)}`);

        await presale.connect(account1).investWithToken(parseEther('500', investDecimals));

        investable = await presale.investable(account1.address);
        const invested = await presale.invested(account1.address);
        console.log(`afterInvest => totalInvestable: ${toEther(totalInvestable, investDecimals)}, investable: ${toEther(investable, investDecimals)}, invested: ${toEther(invested, investDecimals)}`);
        expect(investable).eq(totalInvestable.sub(parseEther('500', investDecimals)));
        expect(invested).eq(parseEther('500', investDecimals));
    });

    it('Invest from account2', async () => {
        const totalInvestable = await presale.totalInvestable(account2.address);
        try {
            await presale.connect(account2).investWithToken(totalInvestable.add(1));    
        } catch (error) {
            console.log("Check limited invest (OK)");
        }
        console.log(toEther(totalInvestable, investDecimals));
        await presale.connect(account2).investWithToken(totalInvestable);

        const totalInvested = await presale.totalInvest();
        console.log("Total Invested: ", toEther(totalInvested, investDecimals));
        
        expect(totalInvested).eq(parseEther('500', investDecimals).add(totalInvestable));
    });

    it('Check softCap and invest from account1 again', async () => {
        try {
            await presale.addLiquidity(false, 1);
        } catch (error) {
            console.log("Check soft cap (OK)");
        }
        const investable = await presale.investable(account1.address);
        await presale.connect(account1).investWithToken(investable);

        const totalInvested = await presale.totalInvest();
        console.log("Total Invested: ", toEther(totalInvested, investDecimals));
    });

    it('Check limited operations before finishing presale', async () => {
        try {
            await presale.setEnableClaim(true, false);
        } catch (error) {
            console.log("Check setEnableClaim (OK)");
        }

        try {
            await presale.connect(account2).claim();
        } catch (error) {
            console.log("Check claim (OK)");
        }

        try {
            await presale.withdrawWantToken();
        } catch (error) {
            console.log("Check withdrawWantToken (OK)");
        }

        try {
            await presale.withdrawInvestToken();
        } catch (error) {
            console.log("Check withdrawInvestToken (OK)");
        }

        try {
            await presale.withdrawPresaleFee();
        } catch (error) {
            console.log("Check withdrawPresaleFee (OK)");
        }
    });

    it('Add Liquidity of invest token', async () => {
        const investBal = await investToken.balanceOf(deployer.address);
        const bnbBal = await deployer.getBalance();

        await presale.addLiquidityDirectly(investToken.address, parseEther('100000', investDecimals), {value: parseEther('5000')});

        expect(await investToken.balanceOf(deployer.address)).eq(investBal.sub(parseEther('100000', investDecimals)));
        const curBal = await deployer.getBalance();
        const expectBal = bnbBal.sub(parseEther('5000'));
        expect(curBal.div(parseEther('1'))).eq(expectBal.div(parseEther('1')));

        const lpInfo = await presale.lpToken(investToken.address);
        console.log(`investLP: ${lpInfo.addr}, totalSupply: ${toEther(lpInfo.totalSupply)}, curBNB: ${toEther(curBal)}`);
        expect(lpInfo.addr).to.not.equal("0x0000000000000000000000000000000000000000");
        expect(lpInfo.totalSupply).gt(0);
    });

    it('Add Liquidity', async () => {
        // Force finish...
        const curTime = await presale.getTimestamp();
        await presale.setStartTime(curTime.sub(10), 1)

        const liquidityAlloc = await presale.liquidityAlloc();
        const totalInvested = await presale.totalInvest();
        const listPrice = await presale.price();
        console.log(`liquidityAlloc: ${liquidityAlloc}, totalInvested: ${toEther(totalInvested, investDecimals)}, price: ${toEther(listPrice)}`);

        const bnbValue = await presale.tokenBNBValue(investToken.address, totalInvested.mul(liquidityAlloc).div(10000));
        console.log('Invest BNB Amount: ', toEther(bnbValue));

        const wantAmount = await presale.requiredWantAmount();
        console.log("Required want token amount: ", toEther(wantAmount, presaleDecimals));

        try {
            await presale.addLiquidity(false, wantAmount.sub(1));
        } catch (error) {
            console.log("Check required want token amount (OK)");
        }

        await presale.addLiquidity(false, wantAmount);
        
        lpSupply = await presale.suppliedLP();
        console.log("Supplied LP: ", toEther(lpSupply));
    });

    it('List investors', async () => {
        const investors = await presale.getInvestorList();
        investors.map(investor => {
            console.log(investor);
        })
    });

    it('Claim', async () => {
        try {
            await presale.connect(account2).claim();
        } catch (error) {
            console.log("Check cliam before enable claim (OK)");
        }

        await presale.setEnableClaim(true, false);

        const cliamable = await presale.claimable(account1.address);
        const wantBal = await presaleToken.balanceOf(account1.address);
        console.log(`Claimable: ${toEther(cliamable, presaleDecimals)}`);
        await presale.connect(account1).claim();
        expect(await presaleToken.balanceOf(account1.address)).eq(wantBal.add(cliamable));
    });

    it('Bulk claim', async () => {
        const cliamable = await presale.claimable(account2.address);
        const wantBal = await presaleToken.balanceOf(account2.address);

        await presale.setEnableClaim(true, true);

        expect(await presaleToken.balanceOf(account2.address)).eq(wantBal.add(cliamable));
    });

    it('Withdraw rest want token', async () => {
        const wantBal = await presaleToken.balanceOf(deployer.address);
        const hardCap = await presale.hardCap();
        const totalSupply = await presale.totalSupply();
        const totalInvest = await presale.totalInvest();
        const restBal = totalSupply.mul(hardCap.sub(totalInvest)).div(hardCap);
        await presale.withdrawWantToken();
        const addedBal = (await presaleToken.balanceOf(deployer.address)).sub(wantBal);
        expect(addedBal.div(10)).eq(restBal.div(10));
        expect(await presaleToken.balanceOf(presale.address)).eq(0);
    });

    it('Withdraw invest token', async () => {
        const beforeBal = await investToken.balanceOf(deployer.address);
        const liquidityAlloc = await presale.liquidityAlloc();
        const totalInvest = await presale.totalInvest();
        const presaleFee = await presale.presaleFee();

        await presale.withdrawInvestToken();

        const expectBal = beforeBal.add(totalInvest.sub(totalInvest.mul(liquidityAlloc).div(10000)).sub(totalInvest.mul(presaleFee).div(10000)));
        const curBal = await investToken.balanceOf(deployer.address);
        expect(curBal).eq(expectBal);
    });

    it('Withdraw presale fee', async () => {
        const beforeBal = await investToken.balanceOf(deployer.address);
        const totalInvest = await presale.totalInvest();
        const presaleFee = await presale.presaleFee();

        await presale.withdrawPresaleFee();

        const expectBal = beforeBal.add(totalInvest.mul(presaleFee).div(10000));
        const curBal = await investToken.balanceOf(deployer.address);
        expect(curBal).eq(expectBal);
    });

    it('Unlock LP', async () => {
        const mocFactory = new MocERC20__factory(deployer);
        const lpToken = mocFactory.attach(await presale.uniswapV2Pair());
        const lpBalance = await lpToken.balanceOf(locker.address);
        
        // expect(await lpToken.totalSupply()).eq(lpSupply);
        expect(lpBalance).eq(lpSupply);

        const balanceOfLocker = await locker.balanceOf(account2.address, lpToken.address);
        console.log(`total: ${toEther(balanceOfLocker.total)}, locked: ${toEther(balanceOfLocker.locked)}, unlocked: ${toEther(balanceOfLocker.unlocked)}`);
        await locker.connect(account2).unlock(lpToken.address);

        expect(await lpToken.balanceOf(locker.address)).eq(lpBalance.sub(balanceOfLocker.total));
    });
});