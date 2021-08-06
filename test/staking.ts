import { expect, use } from 'chai';
import { solidity } from 'ethereum-waffle';

import * as hre from 'hardhat';
import { StakePool } from '../types/ethers-contracts/StakePool';
import { StakePool__factory } from '../types/ethers-contracts/factories/StakePool__factory';
import { MocERC20 } from '../types/ethers-contracts/MocERC20';
import { MocERC20__factory } from '../types/ethers-contracts/factories/MocERC20__factory';
import { BADHINTS } from 'dns';

const { ethers } = hre;

use(solidity);

const parseEther = (val, unit = 18) => {
    return ethers.utils.parseUnits(val, unit);
}

const toEther = (val, unit = 18) => {
    return ethers.utils.formatUnits(val, unit);
}

describe('Testing StakePool...', () => {
    let deployer;
    let account1;
    let account2;
    let beforeBalance;
    let pool: StakePool;
    let token: MocERC20;


    before(async () => {
        let accounts  = await ethers.getSigners();

        deployer = accounts[0];
        account1 = accounts[1];
        account2 = accounts[2];
        console.log(`Deployer => ${deployer.address}`);
        beforeBalance = await deployer.getBalance();
        console.log("Deployer before balance => ", toEther(beforeBalance));
        
        const erc20Factory = new MocERC20__factory(deployer);
        token = await erc20Factory.deploy("Launchpad Token", "IDOTOKEN",18);

        const poolFactory = new StakePool__factory(deployer);
        pool = await poolFactory.deploy(token.address);

        console.log("StakePool address =>", pool.address);
    });

    after(async () => {
        [ deployer ] = await ethers.getSigners();
        const afterBalance = await deployer.getBalance();
        console.log('');
        console.log("Deployer after balance => ", ethers.utils.formatEther(afterBalance));
        const cost = beforeBalance.sub(afterBalance);
        console.log("Test Cost: ", ethers.utils.formatEther(cost));
    });

    it('Distribute 100k assets to each accounts', async () => {
        await token.transfer(account1.address, parseEther('100000'));
        await token.transfer(account2.address, parseEther('100000'));

        await token.approve(pool.address, parseEther('99999999999999'));
        await token.connect(account1).approve(pool.address, parseEther('99999999999999'));
        await token.connect(account2).approve(pool.address, parseEther('99999999999999'));
    });

    it('Add new tier', async () => {
        expect(await pool.tierCount()).eq(5);
        let poolInfo;
        try {
            poolInfo = await pool.poolInfo(5);
        } catch (error) {
            console.log("Check none-existing pool (OK)");
        }

        poolInfo = await pool.poolInfo(4);
        expect(poolInfo.allocPoint).eq(15);
        expect(poolInfo.unitAmount).eq(parseEther('1000'));

        const totalAllocation = await pool.totalAllocPoint();
        await pool.addTier(parseEther('30000'), 1000, 0);
        expect(await pool.tierCount()).eq(6);
        poolInfo = await pool.poolInfo(5);
        expect(poolInfo.allocPoint).eq(1000);
        expect(poolInfo.unitAmount).eq(parseEther('30000'));
        expect(await pool.totalAllocPoint()).eq(totalAllocation.add(1000));
    });

    it('Update existing tier', async () => {
        const poolInfo = await pool.poolInfo(0);
        const totalAlloc = await pool.totalAllocPoint();
        await pool.setLockDuration(0, poolInfo.lockDuration.add(100));
        await pool.setAllocation(0, poolInfo.allocPoint.sub(50));
        await pool.setUnitAmount(0, poolInfo.unitAmount.sub(parseEther('5000')));

        const poolInfo1 = await pool.poolInfo(0);

        expect(poolInfo1.allocPoint).eq(poolInfo.allocPoint.sub(50));
        expect(poolInfo1.lockDuration).eq(poolInfo.lockDuration.add(100));
        expect(poolInfo1.unitAmount).eq(poolInfo.unitAmount.sub(parseEther('5000')));
        expect(await pool.totalAllocPoint()).eq(totalAlloc.sub(poolInfo.allocPoint).add(poolInfo1.allocPoint));
    });

    it('Deposit 2 times', async () => {
        const beforeBal = (await pool.balanceOf(0, deployer.address)).total;
        const stakeUnit = (await pool.poolInfo(0)).unitAmount;
        const stakeAmount = parseEther('32000');

        try {
            await pool.stake(0, stakeUnit.sub(1));
        } catch (error) {
            console.log("Check minimum staking amount (OK)");
        }

        await pool.stake(0, stakeAmount);

        const expectedBal = stakeAmount.sub(stakeAmount.mod(stakeUnit));

        expect((await pool.balanceOf(0, deployer.address)).total).eq(beforeBal.add(expectedBal));
        expect(await pool.totalSupply()).eq(beforeBal.add(expectedBal));
        expect(await pool.userCount(0)).eq(1);

        await pool.stake(0, stakeUnit);

        expect((await pool.balanceOf(0, deployer.address)).total).eq(beforeBal.add(expectedBal).add(stakeUnit));
        expect((await pool.balanceOf(0, deployer.address)).unlocked).eq(0);
        expect((await pool.balanceOf(0, deployer.address)).locked).eq(beforeBal.add(expectedBal).add(stakeUnit));
        expect(await token.balanceOf(pool.address)).eq(beforeBal.add(expectedBal).add(stakeUnit));
        expect(await pool.totalAvailable(0)).eq(0);
        
        await pool.connect(account1).stake(0, stakeUnit);
        expect(await pool.userCount(0)).eq(2);
    });

    it('Deposit with none lock duration', async () => {
        const beforeTotal = await pool.totalSupply();
        const beforeAvailable = await pool.totalAvailable(1);
        const beforeBal = (await pool.balanceOf(1, deployer.address)).total;
        const stakeUnit = (await pool.poolInfo(1)).unitAmount;
        const stakeAmount = parseEther('32000');

        await pool.setLockDuration(1, 0);
        await pool.stake(1, stakeAmount);

        const expectedBal = stakeAmount.sub(stakeAmount.mod(stakeUnit));

        expect(await pool.totalSupply()).eq(beforeTotal.add(expectedBal));
        expect((await pool.balanceOf(1, deployer.address)).total).eq(beforeBal.add(expectedBal));
        expect((await pool.balanceOf(1, deployer.address)).locked).eq(0);
        expect((await pool.balanceOf(1, deployer.address)).unlocked).eq(beforeBal.add(expectedBal));

        await pool.connect(account1).stake(1, stakeUnit);

        expect(await pool.totalAvailable(1)).eq(beforeAvailable.add(expectedBal).add(stakeUnit));
    });

    it('Withdraw', async () => {
        const accountBal = await token.balanceOf(deployer.address);
        const poolBal = await token.balanceOf(pool.address);
        const beforeBal = (await pool.balanceOf(1, deployer.address)).total;
        const stakeUnit = (await pool.poolInfo(1)).unitAmount;
        const withdrawBal = stakeUnit.mul(2); // 20000

        await pool.withdraw(1, withdrawBal);

        expect((await pool.balanceOf(1, deployer.address)).total).eq(beforeBal.sub(withdrawBal));
        expect((await pool.balanceOf(1, deployer.address)).locked).eq(0);
        expect((await pool.balanceOf(1, deployer.address)).unlocked).eq(beforeBal.sub(withdrawBal));
        expect(await token.balanceOf(deployer.address)).eq(accountBal.add(withdrawBal));
        expect(await token.balanceOf(pool.address)).eq(poolBal.sub(withdrawBal));
    });

    it('Withdraw with fee', async () => {
        const fee = 1000;
        await pool.setWithdrawalFee(fee);
        await pool.setFeeRecipient(account2.address);

        const accountBal = await token.balanceOf(deployer.address);
        const accountBal2 = await token.balanceOf(account2.address);
        const poolBal = await token.balanceOf(pool.address);
        const beforeBal = (await pool.balanceOf(1, deployer.address)).total;
        const stakeUnit = (await pool.poolInfo(1)).unitAmount;

        try {
            await pool.withdraw(0, parseEther('30000'));
        } catch (error) {
            console.log("Check withdraw unlocked or exceeded amount (OK)");
        }
        const withdrawBal = stakeUnit.div(2); // 5000

        await pool.withdraw(1, withdrawBal);

        expect((await pool.balanceOf(1, deployer.address)).total).eq(beforeBal.sub(withdrawBal));
        expect((await pool.balanceOf(1, deployer.address)).locked).eq(0);
        expect((await pool.balanceOf(1, deployer.address)).unlocked).eq(beforeBal.sub(withdrawBal));
        expect(await token.balanceOf(deployer.address)).eq(accountBal.add(withdrawBal).sub(withdrawBal.mul(fee).div(10000)));
        expect(await token.balanceOf(pool.address)).eq(poolBal.sub(withdrawBal));
        expect(await token.balanceOf(account2.address)).eq(accountBal2.add(withdrawBal.mul(fee).div(10000)));
    });

    it('WithdrawAll', async () => {
        const bal0 = (await pool.balanceOf(0, deployer.address)).total;
        const bal1 = (await pool.balanceOf(1, deployer.address)).total;
        const poolBal = await token.balanceOf(pool.address);
        const accountBal = await token.balanceOf(deployer.address);
        
        expect(await pool.userCount(0)).eq(2);
        expect(await pool.userCount(1)).eq(2);
        console.log(await pool.getUserList(0));

        await pool.setWithdrawalFee(0);
        await pool.withdrawAll(0);
        await pool.withdrawAll(1);

        expect(await token.balanceOf(pool.address)).eq(poolBal.sub(bal1)); // still locked
        expect((await pool.balanceOf(0, deployer.address)).total).eq(bal0); // still locked
        expect((await pool.balanceOf(1, deployer.address)).total).eq(0);
        expect(await token.balanceOf(deployer.address)).eq(accountBal.add(bal1)); // still locked
        expect(await pool.userCount(0)).eq(2);

        await pool.connect(account1).withdrawAll(0);
        expect(await pool.userCount(0)).eq(2); // still locked
        expect(await pool.userCount(1)).eq(1);
    });
});