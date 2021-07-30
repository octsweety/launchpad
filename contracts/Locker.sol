// SPDX-License-Identifier: MIT
pragma solidity >0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract Locker is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct LockedBalance {
        address token;
        uint256 amount;
        uint256 unlockTime;
    }

    mapping(address => mapping(address => LockedBalance[])) locks;

    function balanceOf(address _user, address _token)
    view public returns (
        uint256 total,
        uint256 unlocked,
        uint256 locked,
        LockedBalance[] memory lockData
    ) {
        LockedBalance[] storage tokenLocks = locks[_user][_token];
        uint256 idx;
        for (uint i = 0; i < tokenLocks.length; i++) {
            if (tokenLocks[i].unlockTime > block.timestamp) {
                if (idx == 0) {
                    lockData = new LockedBalance[](tokenLocks.length - i);
                }
                lockData[idx] = tokenLocks[i];
                locked = locked.add(tokenLocks[i].amount);
            } else {
                unlocked = unlocked.add(tokenLocks[i].amount);
            }
        }
        return (unlocked+locked, unlocked, locked, lockData);
    }

    function lock(address _token, uint _amount, address _keeper, uint _duration) external {
        require(_amount > 0, "!amount");

        uint before = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        _amount = IERC20(_token).balanceOf(address(this)).sub(before);
        
        LockedBalance[] storage tokenLocks = locks[_keeper][_token];
        uint256 unlockTime = block.timestamp.add(_duration);
        tokenLocks.push(LockedBalance({
            token: _token,
            amount: _amount,
            unlockTime: unlockTime
        }));
    }

    function unlock(address _token) external {
        LockedBalance[] storage tokenLocks = locks[msg.sender][_token];
        (uint bal,,,) = balanceOf(msg.sender, _token);
        uint256 amount;
        uint256 length = tokenLocks.length;
        for (uint i = 0; i < length; i++) {
            if (tokenLocks[i].unlockTime > block.timestamp) continue;
            amount = amount.add(tokenLocks[i].amount);
            delete tokenLocks[i];
        }

        if (amount > 0) IERC20(_token).safeTransfer(msg.sender, amount);
        else require(false, "!unlocked");
    }

    function emergencyWithdraw(address _token, uint _amount) external onlyOwner {
        uint balance = IERC20(_token).balanceOf(address(this));
        if (balance < _amount) _amount = balance;
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
}