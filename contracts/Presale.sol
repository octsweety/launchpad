//SPDX-License-Identifier: MIT
pragma solidity >0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "./interface/IStakePool.sol";
import "./interface/IUniswapV2Router02.sol";
import "./interface/IUniswapPair.sol";

interface ILocker {
    function lock(address _token, uint _amount, address _keeper, uint _duration) external;
}

contract Presale is ReentrancyGuard, Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct LockedBalance {
        uint256 amount;
        uint256 unlockTime;
    }

    struct Tier {
        uint supply;
        uint available;
        uint allocation;
    }

    address WBNB = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address liquidityLocker;
    mapping(address => bool) whiteList;
    
    IStakePool public stakePool;
    IERC20 public wantToken;
    IERC20 public investToken = IERC20(WBNB); // WBNB in default
    uint public startTime;
    uint public endTime;
    uint public hardCap;
    uint public softCap;
    uint public totalSupply;
    address immutable keeper;

    uint investRate = 1;
    uint txFee;
    uint presaleFee = 500; // 5%
    uint constant MAX_FEE = 10000;

    uint public totalAllocation;
    Tier[] public tiers;

    uint public totalInvest;
    mapping(address => uint) public invested;
    EnumerableSet.AddressSet investors;
    mapping(address => uint) public claimed;

    bool public enabledClaim = false;
    bool addedLiquidity = false;
    uint liquidityAlloc;
    uint liquidityLockDuration;
    address uniswapV2Pair;
    uint suppliedLP;

    mapping(address => LockedBalance[]) locks;
    uint public totalLocked;
    uint public vestRate;
    uint public vestDuration;

    modifier whenNotStarted {
        require(block.timestamp < startTime, "already started");
        _;
    }

    modifier onProgress {
        require(block.timestamp < endTime && block.timestamp >= startTime, "!progress");
        _;
    }

    modifier whenFinished {
        require(block.timestamp > endTime, "!finished");
        _;
    }

    modifier whenNotFinished {
        require(block.timestamp <= endTime, "!finished");
        _;
    }

    modifier onlyKeeper {
        require(msg.sender == owner() || msg.sender == keeper, "!keeper");
        _;
    }

    modifier whiteListed {
        require(whiteList[msg.sender] == true || msg.sender == owner(), "!permission");
        _;
    }

    constructor (
        address _wantToken,
        address _investToken,
        uint _startTime,
        uint _duration,
        uint _hardCap,
        uint _softCap,
        address _stakePool
    ) public {
        stakePool = IStakePool(_stakePool);
        wantToken = IERC20(_wantToken);
        investToken = IERC20(_investToken);

        require(_duration > 0, "invalid duration");
        startTime = _startTime;
        endTime = _startTime.add(_duration);

        require(_hardCap > _softCap, "invalid caps");
        hardCap = _hardCap;
        softCap = _softCap;

        keeper = msg.sender;
        whiteList[msg.sender] = true;
    }

    function lockedOf(address _user)
    view public returns (
        uint256 total,
        uint256 unlocked,
        uint256 locked,
        LockedBalance[] memory lockData
    ) {
        LockedBalance[] storage tokenLocks = locks[_user];
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

    function getInvestorList() external view onlyKeeper returns (address[] memory) {
        address[] memory investorList = new address[](investors.length());
        for (uint i = 0; i < investors.length(); i++) {
            investorList[i] = investors.at(i);
        }

        return investorList;
    }

    function totalInvestable(address _investor) public view returns (uint) {
        uint tierCount = tiers.length;
        uint amount = 0;

        for (uint i = 0; i < tierCount; i++) {
            uint allocPoint = tiers[i].allocation;
            uint tierTotalAvailable = tiers[i].available;
            if (tierTotalAvailable == 0) continue;
            (,uint balance,) = stakePool.balanceOf(i, _investor);
            amount += hardCap.mul(allocPoint).div(totalAllocation).mul(balance).div(tierTotalAvailable);
        }

        return amount;
    }

    function investable(address _investor) public view returns (uint) {
        uint amount = totalInvestable(_investor);
        if (amount.mul(investRate) <= invested[_investor]) return 0;

        amount = amount.mul(investRate).sub(invested[_investor]);
        if (amount > hardCap.sub(totalInvest)) amount = hardCap.sub(totalInvest);

        return amount;
    }

    function claimable(address _investor) public view returns (uint) {
        if (totalInvest == 0) return 0;

        return totalSupply.mul(invested[_investor]).div(hardCap);
    }

    function investWithToken(uint amount) external onProgress nonReentrant {
        require(address(investToken) != WBNB, "should invest in token");
        require(totalInvest < hardCap, "exceeded hard cap");
        require(amount <= investable(msg.sender), "limited to invest");

        uint before = investToken.balanceOf(address(this));
        investToken.safeTransferFrom(msg.sender, address(this), amount);
        amount = investToken.balanceOf(address(this)).sub(before);

        invested[msg.sender] += amount;
        totalInvest += amount;

        if (!investors.contains(msg.sender)) investors.add(msg.sender);
    }

    function invest() external payable onProgress nonReentrant {
        require(address(investToken) == WBNB, "should invest in BNB");
        require(totalInvest < hardCap, "exceeded hard cap");
        require(msg.value <= investable(msg.sender), "limited to invest");

        invested[msg.sender] += msg.value;
        totalInvest += msg.value;

        if (!investors.contains(msg.sender)) investors.add(msg.sender);
    }

    function claim() external whenFinished nonReentrant {
        require(enabledClaim == true, "still not enabled to claim");
        require(claimed[msg.sender] == 0, "already claimed");

        uint amount = claimable(msg.sender);
        require(amount <= wantToken.balanceOf(address(this)), "exceeded amount to claim");

        if (vestRate > 0) {
            uint vestAmount = amount.mul(vestRate).div(100);
            amount -= vestAmount;
            _vest(vestAmount, msg.sender, vestDuration);
        }
        wantToken.safeTransfer(msg.sender, amount);
        claimed[msg.sender] = block.timestamp;
    }

    function deposit(uint amount) external onlyKeeper whenNotStarted {
        require(amount > 0, "!amount");

        uint before = wantToken.balanceOf(address(this));
        wantToken.safeTransferFrom(msg.sender, address(this), amount);

        // if (txFee > 0) amount = amount.mul(MAX_FEE-txFee).div(MAX_FEE);
        totalSupply += wantToken.balanceOf(address(this)).sub(before);
    }

    function withdrawPresaleToken() external onlyKeeper whenFinished {
        uint investorOwned = totalSupply.mul(totalInvest).div(hardCap);
        uint toSend = totalSupply.sub(investorOwned);
        uint curBal = wantToken.balanceOf(address(this));
        if (toSend > curBal) toSend = curBal;
        wantToken.safeTransfer(msg.sender, toSend);
    }

    function withdrawInvestToken() external onlyKeeper whenFinished {
        if (address(investToken) == WBNB) {
            msg.sender.transfer(totalInvest);
        } else {
            investToken.safeTransfer(msg.sender, totalInvest);
        }
    }

    function unlock() external {
        LockedBalance[] storage tokenLocks = locks[msg.sender];
        (uint bal,,,) = lockedOf(msg.sender);
        uint256 amount;
        uint256 length = tokenLocks.length;
        for (uint i = 0; i < length; i++) {
            if (tokenLocks[i].unlockTime > block.timestamp) continue;
            amount = amount.add(tokenLocks[i].amount);
            delete tokenLocks[i];
        }

        totalLocked -= amount;
        if (amount > 0) wantToken.safeTransfer(msg.sender, amount);
        else require(false, "!unlocked");
    }

    function _bulkTransferClaimable() internal {
        for (uint i = 0; i < investors.length(); i++) {
            address investor = investors.at(i);
            if (claimed[investor] > 0) continue; // already claimed

            uint amount = claimable(investor);
            require(amount <= wantToken.balanceOf(address(this)), "exceeded amount to claim");

            if (vestRate > 0) {
                uint vestAmount = amount.mul(vestRate).div(100);
                amount -= vestAmount;
                _vest(vestAmount, investor, vestDuration);
            }
            wantToken.safeTransfer(investor, amount);
            claimed[investor] = block.timestamp;
        }
    }

    function _vest(uint _amount, address _keeper, uint _duration) internal {
        LockedBalance[] storage tokenLocks = locks[_keeper];
        uint256 unlockTime = block.timestamp.add(_duration);
        tokenLocks.push(LockedBalance({
            amount: _amount,
            unlockTime: unlockTime
        }));
        totalLocked += _amount;
    }

    function updateTiers() external whiteListed whenNotStarted {
        delete tiers;
        totalAllocation = stakePool.totalAllocPoint();

        uint tierCount = stakePool.tierCount();
        for (uint i = 0; i < tierCount; i++) {
            (,uint allocPoint,,uint tierSupply) = stakePool.poolInfo(i);
            uint tierTotalAvailable = stakePool.totalAvailable(i);
            tiers.push(Tier({supply: tierSupply, available: tierTotalAvailable, allocation: allocPoint}));
        }
    }

    function setEnableClaim(bool _flag, bool _isBulk, uint _vestRate, uint _vestDuration) external whiteListed whenFinished {
        enabledClaim = _flag;

        if (_flag == true && _isBulk == true) {
            _bulkTransferClaimable();
        }

        vestRate = _vestRate;
        vestDuration = _vestDuration;
    }

    function setHardCap(uint _cap) external whiteListed whenNotFinished {
        require(_cap > softCap, "invalid soft cap");
        hardCap = _cap;
    }

    function setSoftCap(uint _cap) external whiteListed {
        require(_cap < hardCap, "invalid soft cap");
        softCap = _cap;
    }

    function setStartTime(uint _startTime, uint _duration) external whiteListed {
        startTime = _startTime;
        endTime = _startTime.add(_duration);
    }

    function setStakePool(address _pool) external onlyOwner {
        stakePool = IStakePool(_pool);
    }

    function setWhiteList(address _user, bool _flag) external onlyOwner {
        whiteList[_user] = _flag;
    }

    receive() external payable {}
}