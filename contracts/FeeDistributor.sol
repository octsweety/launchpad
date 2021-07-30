// SPDX-License-Identifier: MIT
pragma solidity >0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interface/IUniswapV2Router02.sol";
import "./interface/IUniswapPair.sol";

contract FeeDistributor is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public unirouter = address(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    IERC20 public constant WBNB = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    uint public minPendingAmount = 10000;

    constructor () public {
    }

    function setMinPendingAmount(uint _amount) external onlyOwner {
        minPendingAmount = _amount;
    }

    /**
     * @dev Updates router that will be used for swaps.
     * @param _unirouter new unirouter address.
     */
    function setUnirouter(address _unirouter) external onlyOwner {
        unirouter = _unirouter;
    }

    function balanceOf(address _token) public view returns (uint) {
        return IERC20(_token).balanceOf(address(this));
    }

    function withdraw(address _token, uint _amount, address _recipient) external onlyOwner {
        uint balance = IERC20(_token).balanceOf(address(this));
        if (balance < _amount) _amount = balance;
        IERC20(_token).safeTransfer(_recipient, _amount);
    }

    function distributeToken(address _recipient, address _token, uint _percentage) external onlyOwner {
        require(_recipient != address(0), "Invalid address");
        require(_percentage < 100, "!percentage");
        
        uint tokenAmount = IERC20(_token).balanceOf(address(this));
        uint wbnbAmount = swapToWBNB(_token, tokenAmount.mul(_percentage).div(100));
        if (wbnbAmount == 0) return;

        WBNB.safeTransfer(_recipient, wbnbAmount);
    }

    function swapToWBNB(address _token, uint _amount) internal returns (uint) {
        if (_token == address(WBNB)) return 0;

        uint curAmount = IERC20(_token).balanceOf(address(this));
        if (_amount > curAmount) _amount = curAmount;
        require(_amount >= minPendingAmount, "too small amount");

        address[] memory route = new address[](2);
        route[0] = _token; route[1] = address(WBNB);

        uint wbnbAmount = IUniswapV2Router02(unirouter).getAmountsOut(_amount, route)[1];
        if (wbnbAmount == 0) return 0;

        IERC20(_token).safeApprove(unirouter, 0);
        IERC20(_token).safeApprove(unirouter, _amount);
        IUniswapV2Router02(unirouter).swapExactTokensForTokens(_amount, 0, route, address(this), block.timestamp);

        return WBNB.balanceOf(address(this));
    }
}