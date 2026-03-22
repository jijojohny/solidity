// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Oracle returns the mark price of the index asset in USD (8 decimals, e.g. 2000e8 = $2000).
interface IPriceOracle {
    function latestAnswer() external view returns (int256);
}
