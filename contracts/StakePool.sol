//SPDX-License-Identifier: Unlicense
pragma solidity >0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

contract StakePool is ReentrancyGuard, Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct LockedBalance {
        uint256 amount;
        uint256 unlockTime;
    }

    struct PoolInfo {
        uint256 unitAmount;
        uint256 allocPoint;
        uint256 lockDuration;
        uint256 totalSupply;
    }

    IERC20 public stakingToken;
    uint256 public withdrawalFee;
    uint256 public txFee;
    uint256 public constant MAX_FEE = 10000;

    PoolInfo[] public poolInfo;
    uint256 public totalAllocPoint;

    mapping(uint256 => mapping(address => uint256)) balances;
    mapping(uint256 => mapping(address => LockedBalance[])) userLocks;
    mapping(uint256 => EnumerableSet.AddressSet) users;

    address public feeRecipient;

    event Staked(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed pid, uint256 amount);

    modifier updateUserList(uint pid) {
        _;
        if (balances[pid][msg.sender] > 0) _checkOrAddUser(pid, msg.sender);
        else _removeUser(pid, msg.sender);
    }

    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
        feeRecipient = msg.sender;
        
        // Add Tiers
        addTier(uint(20000 ether), 750, uint(3 days));
        addTier(uint(10000 ether), 300, uint(3 days));
        addTier(uint(5000 ether), 130, uint(3 days));
        addTier(uint(2000 ether), 40, uint(3 days));
        addTier(uint(1000 ether), 15, uint(3 days));
    }

    function addTier(uint256 _unitAmount, uint256 _allocPoint, uint256 _lockDuration) public onlyOwner {
        poolInfo.push(
            PoolInfo({
                unitAmount: _unitAmount,
                allocPoint: _allocPoint,
                lockDuration: _lockDuration,
                totalSupply: 0
            })
        );

        totalAllocPoint += _allocPoint;
    }

    function tierCount() external view returns (uint) {
        return poolInfo.length;
    }
    
    function setLockDuration(uint pid, uint256 _lockDuration) external onlyOwner {
        poolInfo[pid].lockDuration = _lockDuration;
    }

    function setAllocation(uint pid, uint _allocation) external onlyOwner {
        totalAllocPoint -= poolInfo[pid].allocPoint;
        poolInfo[pid].allocPoint = _allocation;
        totalAllocPoint += _allocation;
    }

    function setUnitAmount(uint pid, uint _amount) external onlyOwner {
        poolInfo[pid].unitAmount = _amount;
    }

    function balance(uint pid) public view returns (uint256) {
        return poolInfo[pid].totalSupply;
    }

    function totalSupply() external view returns (uint256) {
        uint _totalSupply = 0;
        for (uint256 i = 0; i < poolInfo.length; i++) {
            _totalSupply += poolInfo[i].totalSupply;
        }
        return _totalSupply;
    }

    function userCount(uint pid) external view returns (uint256) {
        return users[pid].length();
    }

    function getUserList(uint pid) external view onlyOwner returns (address[] memory) {
        address[] memory userList = new address[](users[pid].length());
        for (uint i = 0; i < users[pid].length(); i++) {
            userList[i] = users[pid].at(i);
        }

        return userList;
    }

    function balanceOf(uint pid, address user)
    view public returns (
        uint256 total,
        uint256 unlocked,
        uint256 locked
    ) {
        LockedBalance[] storage locks = userLocks[pid][user];
        for (uint i = 0; i < locks.length; i++) {
            if (locks[i].unlockTime > block.timestamp) {
                locked = locked.add(locks[i].amount);
            } else {
                unlocked = unlocked.add(locks[i].amount);
            }
        }
        return (balances[pid][user], unlocked, locked);
    }

    function totalAvailable(uint pid) external view returns (uint) {
        uint _totalAvvailable = 0;
        for (uint i = 0; i < users[pid].length(); i++) {
            (,uint unlocked,) = balanceOf(pid, users[pid].at(i));
            _totalAvvailable += unlocked;
        }

        return _totalAvvailable;
    }

    function stake(uint256 pid, uint256 amount) external whenNotPaused nonReentrant updateUserList(pid) {
        require(amount >= poolInfo[pid].unitAmount, "!amount");

        amount -= amount % poolInfo[pid].unitAmount; // Should be x times of unitAmount
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        if (txFee > 0) amount = amount.mul(MAX_FEE-txFee).div(MAX_FEE);
        balances[pid][msg.sender] += amount;
        poolInfo[pid].totalSupply = poolInfo[pid].totalSupply.add(amount);
        
        uint256 unlockTime = block.timestamp.add(poolInfo[pid].lockDuration);
        uint256 idx = userLocks[pid][msg.sender].length;
        userLocks[pid][msg.sender].push(LockedBalance({amount: amount, unlockTime: unlockTime}));

        emit Staked(msg.sender, pid, amount);
    }

    function withdraw(uint256 pid, uint256 amount) external nonReentrant updateUserList(pid) {
        require(amount > 0, "!amount");
        
        uint bal = balances[pid][msg.sender];
        if (amount > bal) amount = bal;

        uint256 remaining = amount;
        LockedBalance[] storage locks = userLocks[pid][msg.sender];
        for (uint i = 0; i < locks.length; i++) {
            uint256 locked = locks[i].amount;
            require(locks[i].unlockTime <= block.timestamp && remaining > 0, "no unlocked balance");
            if (remaining <= locked) {
                locks[i].amount = locked.sub(remaining);
                if (locks[i].amount == 0) delete locks[i];
                break;
            } else {
                delete locks[i];
                remaining = remaining.sub(locked);
                if (remaining == 0) break;
            }
        }

        balances[pid][msg.sender] = balances[pid][msg.sender].sub(amount);
        poolInfo[pid].totalSupply = poolInfo[pid].totalSupply.sub(amount);

        if (withdrawalFee > 0) {
            stakingToken.safeTransfer(feeRecipient, amount.mul(withdrawalFee).div(MAX_FEE));
            amount = amount.mul(MAX_FEE-withdrawalFee).div(MAX_FEE);
        }
        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, pid, amount);
    }

    function withdrawAll(uint256 pid) external nonReentrant updateUserList(pid) {
        require(balances[pid][msg.sender] > 0, "!amount");

        LockedBalance[] storage locks = userLocks[pid][msg.sender];
        uint bal = balances[pid][msg.sender];
        uint256 amount;
        uint256 length = locks.length;
        if (locks[length-1].unlockTime <= block.timestamp) {
            amount = bal;
            delete userLocks[pid][msg.sender];
        } else {
            for (uint i = 0; i < length; i++) {
                if (locks[i].unlockTime > block.timestamp) break;
                amount = amount.add(locks[i].amount);
                delete locks[i];
            }
        }
        balances[pid][msg.sender] = balances[pid][msg.sender].sub(amount);
        poolInfo[pid].totalSupply = poolInfo[pid].totalSupply.sub(amount);

        if (withdrawalFee > 0) {
            stakingToken.safeTransfer(feeRecipient, amount.mul(withdrawalFee).div(MAX_FEE));
            amount = amount.mul(MAX_FEE-withdrawalFee).div(MAX_FEE);
        }
        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, pid, amount);
    }

    function _removeUser(uint pid, address _user) internal {
        if (users[pid].contains(_user) == true) {
            users[pid].remove(_user);
        }
    }

    function _checkOrAddUser(uint pid, address _user) internal {
        if (users[pid].contains(_user) == false) {
            users[pid].add(_user);
        }
    }

    function setTxFee(uint256 _fee) external onlyOwner {
        require(_fee < MAX_FEE, "invalid fee");

        txFee = _fee;
    }

    function setWithdrawalFee(uint256 _fee) external onlyOwner {
        require(_fee < MAX_FEE, "invalid fee");

        withdrawalFee = _fee;
    }

    function setFeeRecipient(address _recipient) external onlyOwner {
        feeRecipient = _recipient;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}