import { expect, use } from 'chai';
import { solidity } from 'ethereum-waffle';

import * as hre from 'hardhat';
import { Locker } from '../types/ethers-contracts/Locker';
import { Locker__factory } from '../types/ethers-contracts/factories/Locker__factory';
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

describe('Testing Locker...', () => {
    let deployer;
    let account1;
    let account2;
    let beforeBalance;
    let pool: Locker;
    let token1: MocERC20;
    let token2: MocERC20;
    let token3: MocERC20;


    before(async () => {
        let accounts  = await ethers.getSigners();

        deployer = accounts[0];
        account1 = accounts[1];
        account2 = accounts[2];
        console.log(`Deployer => ${deployer.address}`);
        beforeBalance = await deployer.getBalance();
        console.log("Deployer before balance => ", toEther(beforeBalance));
        
        const erc20Factory = new MocERC20__factory(deployer);
        token1 = await erc20Factory.deploy("Lock Token1", "TOKEN1",18);
        token2 = await erc20Factory.deploy("Lock Token2", "TOKEN2",18);
        token3 = await erc20Factory.deploy("Lock Token3", "TOKEN3",18);

        const poolFactory = new Locker__factory(deployer);
        pool = await poolFactory.deploy();

        console.log("Locker address =>", pool.address);
    });

    after(async () => {
        [ deployer ] = await ethers.getSigners();
        const afterBalance = await deployer.getBalance();
        console.log('');
        console.log("Deployer after balance => ", ethers.utils.formatEther(afterBalance));
        const cost = beforeBalance.sub(afterBalance);
        console.log("Test Cost: ", ethers.utils.formatEther(cost));
    });

    it('Approve tokens to the pool', async () => {
        await token1.approve(pool.address, parseEther('99999999999999'));
        await token2.approve(pool.address, parseEther('99999999999999'));
        await token3.approve(pool.address, parseEther('99999999999999'));
    });

    it('Lock tokens', async () => {
        const beforeBal1 = await pool.balanceOf(deployer.address, token1.address);
        const beforeBal2 = await pool.balanceOf(deployer.address, token2.address);
        const beforeBal3 = await pool.balanceOf(deployer.address, token3.address);

        const locking1 = parseEther('1000');
        const locking2 = parseEther('2000');
        const locking3 = parseEther('3000');

        await pool.lock(token1.address, locking1, deployer.address, 300);
        await pool.lock(token2.address, locking2, account1.address, 300);
        await pool.lock(token3.address, locking3, account2.address, 300);

        const afterBal1 = await pool.balanceOf(deployer.address, token1.address);
        const afterBal2 = await pool.balanceOf(account1.address, token2.address);
        const afterBal3 = await pool.balanceOf(account2.address, token3.address);

        expect(afterBal1.total).eq(locking1);
        expect(afterBal1.locked).eq(locking1);
        expect(afterBal1.unlocked).eq(0);

        expect(afterBal2.total).eq(locking2);
        expect(afterBal2.locked).eq(locking2);
        expect(afterBal2.unlocked).eq(0);

        expect(afterBal3.total).eq(locking3);
        expect(afterBal3.locked).eq(locking3);
        expect(afterBal3.unlocked).eq(0);
    });

    it('Check withdraw locked token', async () => {
        try {
            await pool.unlock(token1.address);
        } catch (error) {
            // OK
            return;
        }
        throw new Error("(FAILE)");
    });

    it('Lock with zero period', async () => {
        const beforeBal1 = await pool.balanceOf(account1.address, token1.address);
        const locking1 = parseEther('1000');

        await pool.lock(token1.address, locking1, account1.address, 0);
        const afterBal1 = await pool.balanceOf(account1.address, token1.address);

        expect(afterBal1.total).eq(beforeBal1.total.add(locking1));
        expect(afterBal1.unlocked).eq(beforeBal1.unlocked.add(locking1));
        expect(afterBal1.locked).eq(beforeBal1.locked);
    });

    it('Unlock', async () => {
        const beforeToken1 = await token1.balanceOf(account1.address);
        const beforeBal1 = await pool.balanceOf(account1.address, token1.address);

        await pool.connect(account1).unlock(token1.address);

        const afterBal1 = await pool.balanceOf(account1.address, token1.address);
        const afterToken1 = await token1.balanceOf(account1.address);

        expect(afterToken1).eq(beforeToken1.add(beforeBal1.unlocked));
        expect(afterBal1.total).eq(beforeBal1.total.sub(beforeBal1.unlocked));
    });
});