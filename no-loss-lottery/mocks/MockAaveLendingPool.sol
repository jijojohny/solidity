// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./MockERC20.sol";

/**
 * @title MockAaveLendingPool
 * @dev Mock Aave lending pool for testing NoLossLottery
 * Simulates yield generation by allowing manual yield injection
 */
contract MockAaveLendingPool {
    MockERC20 public underlyingToken;
    MockERC20 public aToken;

    mapping(address => uint256) public deposits;
    uint256 public totalDeposited;
    uint256 public simulatedYield;

    event Supply(address indexed user, address indexed asset, uint256 amount);
    event Withdraw(address indexed user, address indexed asset, uint256 amount);

    constructor(address _underlyingToken, address _aToken) {
        underlyingToken = MockERC20(_underlyingToken);
        aToken = MockERC20(_aToken);
    }

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 /* referralCode */
    ) external {
        require(asset == address(underlyingToken), "Invalid asset");
        require(
            underlyingToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        deposits[onBehalfOf] += amount;
        totalDeposited += amount;

        aToken.mint(onBehalfOf, amount);

        emit Supply(onBehalfOf, asset, amount);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        require(asset == address(underlyingToken), "Invalid asset");
        require(aToken.balanceOf(msg.sender) >= amount, "Insufficient aToken balance");

        aToken.burn(msg.sender, amount);

        if (deposits[msg.sender] >= amount) {
            deposits[msg.sender] -= amount;
            totalDeposited -= amount;
        }

        underlyingToken.transfer(to, amount);

        emit Withdraw(to, asset, amount);
        return amount;
    }

    function addYield(uint256 _amount) external {
        simulatedYield += _amount;
        underlyingToken.mint(address(this), _amount);
        aToken.mint(msg.sender, _amount);
    }

    function getReserveData(address /* asset */) external view returns (ReserveData memory) {
        return ReserveData({
            configuration: 0,
            liquidityIndex: 1e27,
            currentLiquidityRate: 5e25,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 7e25,
            currentStableBorrowRate: 8e25,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 1,
            aTokenAddress: address(aToken),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(0),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
    }

    struct ReserveData {
        uint256 configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }
}
