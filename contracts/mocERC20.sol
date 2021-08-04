//SPDX-License-Identifier: Unlicense
pragma solidity >0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract mocERC20 is ERC20 {
    constructor() ERC20("Mockup ERC20", "mocERC20") public {
        _mint(msg.sender, 1000000 * 1e18);
    }

    function getBlock() external view returns (uint) {
        return block.number;
    }
    
    function getTimestamp() external view returns (uint) {
        return block.timestamp;
    }
}