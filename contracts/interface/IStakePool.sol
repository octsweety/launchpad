// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

interface IStakePool {
    function totalAllocPoint() external view returns (uint);
    function tierCount() external view returns (uint);
    function poolInfo(uint pid)
    external view returns (
        uint unitAmount,
        uint allocPoint,
        uint lockDuration,
        uint totalSupply
    );
    function totalSupply() external view returns (uint);
    function totalAvailable(uint pid) external view returns (uint);
    function balanceOf(uint pid, address user)
    view external returns (
        uint256 total,
        uint256 unlocked,
        uint256 locked
    );
}