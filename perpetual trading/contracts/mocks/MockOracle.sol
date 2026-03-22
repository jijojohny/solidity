// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPriceOracle.sol";

contract MockOracle is IPriceOracle {
    int256 public answer;

    function setAnswer(int256 _answer) external {
        answer = _answer;
    }

    function latestAnswer() external view override returns (int256) {
        return answer;
    }
}
