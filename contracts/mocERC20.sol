//SPDX-License-Identifier: Unlicense
pragma solidity >0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract mocERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) public {
        _setupDecimals(_decimals);
        _mint(msg.sender, 100000000 * (10 ** _decimals));
    }

    function getBlock() external view returns (uint) {
        return block.number;
    }
    
    function getTimestamp() external view returns (uint) {
        return block.timestamp;
    }
}