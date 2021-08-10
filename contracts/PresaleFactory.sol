// SPDX-License-Identifier: MIT
pragma solidity >0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./PresaleV2.sol";

contract PresaleFactory is Ownable {
    struct PresaleInfo {
        string name;
        address wantToken;
        address investToken;
        uint startTime;
        uint duration;
        uint hardCap;
        uint softCap;
        uint price;
        uint liquidityAlloc;
        uint lockDuration;
        address keeper;
    }

    PresaleInfo[] public presales;

    address public locker;
    address public staker;

    constructor (
        address _locker,
        address _staker
    ) public {
        staker = _staker;
        locker = _locker;
    }

    function setLocker(address _locker) external onlyOwner {
        locker = _locker;
    }

    function setStaker(address _staker) external onlyOwner {
        staker = _staker;
    }

    function deploy(
        string memory _name,
        address _wantToken,
        address _investToken,
        uint _startTime,
        uint _duration,
        uint _hardCap,
        uint _softCap,
        uint _price,
        uint _liquidityAlloc,
        uint _lockDuration,
        address _keeper
    ) external returns (address) {
        require(msg.sender == owner(), "!owner");
        
        PresaleV2 presale = new PresaleV2(
            _wantToken,
            _investToken,
            _startTime,
            _duration,
            _hardCap,
            _softCap,
            _price,
            _liquidityAlloc,
            locker,
            _lockDuration,
            staker,
            _keeper
        );
        presale.transferOwnership(msg.sender);
        presales.push(PresaleInfo({
            name: _name,
            wantToken: _wantToken,
            investToken: _investToken,
            startTime: _startTime,
            duration: _duration,
            hardCap: _hardCap,
            softCap: _softCap,
            price: _price,
            liquidityAlloc: _liquidityAlloc,
            lockDuration: _lockDuration,
            keeper: _keeper
        }));

        return address(presale);
    }
}
