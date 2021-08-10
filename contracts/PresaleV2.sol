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

contract PresaleV2 is ReentrancyGuard, Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct Tier {
        uint supply;
        uint available;
        uint allocation;
    }

    address WBNB = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IUniswapV2Router02 public uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public liquidityLocker;
    mapping(address => bool) whiteList;
    
    IStakePool public stakePool;
    IERC20 public wantToken;
    IERC20 public investToken = IERC20(WBNB); // WBNB in default
    uint public startTime;
    uint public endTime;
    uint public immutable hardCap;
    uint public softCap;
    uint public totalSupply;
    uint public price;
    address public immutable keeper;

    uint public investRate = 1;
    uint public txFee;
    uint public presaleFee = 500; // 5%
    uint public constant MAX_FEE = 10000;

    uint public totalAllocation;
    Tier[] public tiers;

    uint public totalInvest;
    mapping(address => uint) public invested;
    EnumerableSet.AddressSet investors;
    mapping(address => uint) public claimed;

    bool public enabledClaim = false;
    bool public addedLiquidity = false;
    uint public liquidityAlloc;
    uint public liquidityLockDuration;
    address public uniswapV2Pair;
    uint public suppliedLP;

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
        require(msg.sender == owner() || whiteList[msg.sender] == true || msg.sender == keeper, "!keeper");
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
        uint _price,
        uint _liquidityAlloc,
        address _liquidityLocker,
        uint _liquidityLockDuration,
        address _stakePool,
        address _keeper
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

        price = _price;
        liquidityAlloc = _liquidityAlloc;
        liquidityLocker = _liquidityLocker;
        liquidityLockDuration = _liquidityLockDuration;
        keeper = _keeper;

        whiteList[msg.sender] = true;
    }

    function getInvestorList() external view onlyKeeper returns (address[] memory) {
        address[] memory investorList = new address[](investors.length());
        for (uint i = 0; i < investors.length(); i++) {
            investorList[i] = investors.at(i);
        }

        return investorList;
    }

    function requiredWantAmount() external view returns (uint) {
        uint liquidityForInvest = totalInvest.mul(liquidityAlloc).div(MAX_FEE);
        uint wantDecimals = ERC20(address(wantToken)).decimals();
        uint investDecimals = address(investToken) == WBNB ? 18 : ERC20(address(investToken)).decimals();
        uint decimalsDiff = investDecimals > wantDecimals ? investDecimals.sub(wantDecimals) : wantDecimals.sub(investDecimals);
        uint liquidityForWant;
        if (investDecimals > wantDecimals) {
            liquidityForWant = liquidityForInvest.mul(1e18).div(price).div(10**decimalsDiff);
        } else {
            liquidityForWant = liquidityForInvest.mul(1e18).div(price).mul(10**decimalsDiff);
        }
        return liquidityForWant;
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

    function withdrawWantToken() external onlyKeeper whenFinished {
        uint investorOwned = totalSupply.mul(totalInvest).div(hardCap);
        uint toSend = totalSupply.sub(investorOwned);
        uint curBal = wantToken.balanceOf(address(this));
        if (toSend > curBal) toSend = curBal;
        wantToken.safeTransfer(msg.sender, toSend);
    }

    function withdrawInvestToken() external onlyKeeper whenFinished {
        require(addedLiquidity == true, "!withdrawable");
        uint liquidated = totalInvest.mul(liquidityAlloc).div(MAX_FEE);
        uint withdrawable = totalInvest.sub(liquidated).sub(totalInvest.mul(presaleFee).div(MAX_FEE));
        if (address(investToken) == WBNB) {
            msg.sender.transfer(withdrawable);
        } else {
            investToken.safeTransfer(msg.sender, withdrawable);
        }
    }

    function withdrawPresaleFee() external whiteListed {
        require(addedLiquidity == true, "!withdrawable");
        if (address(investToken) == WBNB) {
            msg.sender.transfer(totalInvest.mul(presaleFee).div(MAX_FEE));
        } else {
            investToken.safeTransfer(msg.sender, totalInvest.mul(presaleFee).div(MAX_FEE));
        }
    }

    function addLiquidity(bool _force, uint _amount) external whiteListed whenFinished {
        require(_force == true || totalInvest > softCap, "!failed presale");

        if (IUniswapV2Factory(uniswapV2Router.factory()).getPair(address(wantToken), uniswapV2Router.WETH()) == address(0)) {
            uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
                .createPair(address(wantToken), uniswapV2Router.WETH());
        }

        uint liquidityForInvest = totalInvest.mul(liquidityAlloc).div(MAX_FEE);
        uint wantDecimals = ERC20(address(wantToken)).decimals();
        uint investDecimals = address(investToken) == WBNB ? 18 : ERC20(address(investToken)).decimals();
        uint decimalsDiff = investDecimals > wantDecimals ? investDecimals.sub(wantDecimals) : wantDecimals.sub(investDecimals);
        uint liquidityForWant;
        if (investDecimals > wantDecimals) {
            liquidityForWant = liquidityForInvest.mul(1e18).div(price).div(10**decimalsDiff);
        } else {
            liquidityForWant = liquidityForInvest.mul(1e18).div(price).mul(10**decimalsDiff);
        }

        require(_amount >= liquidityForWant, "!required amount");
        wantToken.safeTransferFrom(msg.sender, address(this), liquidityForWant);

        if (address(investToken) == WBNB) {
            _addLiquidity(address(wantToken), liquidityForWant, liquidityForInvest);
        } else {
            _swapAndLiquidity(liquidityForWant, liquidityForInvest);
        }

        suppliedLP = IERC20(uniswapV2Pair).balanceOf(address(this));
        IERC20(uniswapV2Pair).safeApprove(liquidityLocker, suppliedLP);
        ILocker(liquidityLocker).lock(uniswapV2Pair, suppliedLP, keeper, liquidityLockDuration);

        addedLiquidity = true;
    }

    function _swapAndLiquidity(uint wantTokens, uint investTokens) internal {
        address[] memory path = new address[](2);
        path[0] = address(investToken);
        path[1] = uniswapV2Router.WETH();
        // uint beforeBalance = IERC20(uniswapV2Router.WETH()).balanceOf(address(this));
        uint beforeBalance = address(this).balance;

        investToken.safeApprove(address(uniswapV2Router), investTokens);

        // make the swap
        // uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            investTokens,
            0, // accept any amount of ETH
            path,
            address(this), // The contract
            block.timestamp
        );

        // _addLiquidityWithWBNB(address(wantToken), wantTokens, IERC20(uniswapV2Router.WETH()).balanceOf(address(this)).sub(beforeBalance));
        _addLiquidity(address(wantToken), wantTokens, address(this).balance.sub(beforeBalance));
    }

    function addLiquidityDirectly(address _token, uint _amount) external payable {
        address pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(_token, uniswapV2Router.WETH());
        if (pair == address(0)) {
            pair = IUniswapV2Factory(uniswapV2Router.factory())
                .createPair(address(_token), uniswapV2Router.WETH());
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        _addLiquidity(_token, _amount, msg.value);

        uint lpBal = IERC20(pair).balanceOf(address(this));
        IERC20(pair).safeTransfer(msg.sender, lpBal);
    }

    function lpToken(address _token) external view returns (address addr, uint totalSupply) {
        address lp = IUniswapV2Factory(uniswapV2Router.factory()).getPair(_token, uniswapV2Router.WETH());
        return (lp, IERC20(lp).totalSupply());
    }

    function tokenBNBValue(address _token, uint _amount) external view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = _token;
        path[1] = uniswapV2Router.WETH();
        return uniswapV2Router.getAmountsOut(_amount, path)[1];
    }

    function _addLiquidity(address _token, uint _tokenAmount, uint _bnbAmount) internal {
        // approve token transfer to cover all possible scenarios
        IERC20(_token).safeApprove(address(uniswapV2Router), _tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: _bnbAmount}(
            _token,
            _tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function _addLiquidityWithWBNB(address _token, uint _tokenAmount, uint _bnbAmount) internal {
        // approve token transfer to cover all possible scenarios
        IERC20(_token).safeApprove(address(uniswapV2Router), _tokenAmount);
        IERC20(uniswapV2Router.WETH()).safeApprove(address(uniswapV2Router), _bnbAmount);

        // add the liquidity
        uniswapV2Router.addLiquidity(
            _token,
            uniswapV2Router.WETH(),
            _tokenAmount,
            _bnbAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function _bulkTransferClaimable() internal {
        for (uint i = 0; i < investors.length(); i++) {
            address investor = investors.at(i);
            if (claimed[investor] > 0) continue; // already claimed

            uint amount = claimable(investor);
            require(amount <= wantToken.balanceOf(address(this)), "exceeded amount to claim");

            wantToken.safeTransfer(investor, amount);
            claimed[investor] = block.timestamp;
        }
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

    function setEnableClaim(bool _flag, bool _isBulk) external whiteListed whenFinished {
        enabledClaim = _flag;

        if (_flag == true && _isBulk == true) {
            _bulkTransferClaimable();
        }
    }

    function setSoftCap(uint _cap) external whiteListed {
        require(_cap < hardCap, "invalid soft cap");
        softCap = _cap;
    }

    function setInvestToken(address _token) external whiteListed whenNotStarted {
        investToken = IERC20(_token);
    }

    function setTxFee(uint256 _fee) external whiteListed whenNotStarted {
        require(_fee < MAX_FEE, "invalid fee");
        txFee = _fee;
    }

    function setInvestRate(uint _rate) external whiteListed {
        require(_rate > 0, "!rate");
        investRate = _rate;
    }

    function setPrice(uint _price) external whiteListed {
        require(_price > 0, "!price");
        price = _price;
    }

    function setPresaleFee(uint _fee) external whiteListed {
        require(_fee < MAX_FEE, "!fee");
        presaleFee = _fee;
    }

    function setLiquidityAlloc(uint _allocation) external whiteListed {
        require(_allocation < MAX_FEE, "!allocation");
        liquidityAlloc = _allocation;
    }

    function setUniswapRouter(address _router) external whiteListed {
        uniswapV2Router = IUniswapV2Router02(_router);
    }

    function setLquidityLocker(address _locker) external whiteListed {
        liquidityLocker = _locker;
    }

    function setLiquidityLockDuration(uint _duration) external whiteListed {
        liquidityLockDuration = _duration;
    }

    function setStartTime(uint _startTime, uint _duration) external whiteListed {
        startTime = _startTime;
        endTime = _startTime.add(_duration);
    }

    function setWhiteList(address _user, bool _flag) external onlyOwner {
        whiteList[_user] = _flag;
    }

    // Temp Function
    function getTimestamp() external view returns (uint) {
        return block.timestamp;
    }

    receive() external payable {}
}