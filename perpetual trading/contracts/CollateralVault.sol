// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC20.sol";

/// @title CollateralVault
/// @notice Holds collateral ERC20. Perpetual market locks margin per user; users deposit and withdraw free balance.
contract CollateralVault {
    IERC20 public immutable collateralToken;
    address public market;

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public marginLocked;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event MarketSet(address indexed market);

    constructor(address _collateralToken) {
        require(_collateralToken != address(0), "zero token");
        collateralToken = IERC20(_collateralToken);
    }

    modifier onlyMarket() {
        require(msg.sender == market, "only market");
        _;
    }

    function setMarket(address _market) external {
        require(market == address(0), "market set");
        require(_market != address(0), "zero market");
        market = _market;
        emit MarketSet(_market);
    }

    function deposit(uint256 amount) external {
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "transferFrom");
        balanceOf[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        uint256 freeBal = balanceOf[msg.sender] - marginLocked[msg.sender];
        require(freeBal >= amount, "insufficient free");
        balanceOf[msg.sender] -= amount;
        require(collateralToken.transfer(msg.sender, amount), "transfer");
        emit Withdrawn(msg.sender, amount);
    }

    function lockMargin(address user, uint256 amount) external onlyMarket {
        require(balanceOf[user] - marginLocked[user] >= amount, "insufficient free");
        marginLocked[user] += amount;
    }

    /// @notice Release locked margin; apply realized PnL (margin already counted in balanceOf).
    function unlockAndCredit(address user, uint256 marginAmount, int256 pnl) external onlyMarket {
        require(marginLocked[user] >= marginAmount, "locked");
        marginLocked[user] -= marginAmount;
        if (pnl >= 0) {
            balanceOf[user] += uint256(pnl);
        } else {
            uint256 loss = uint256(-pnl);
            balanceOf[user] -= loss;
        }
    }

    /// @notice Liquidation: user loses locked margin; ERC20 sent to liquidator, insurance, and remainder.
    function seizeAndPay(
        address user,
        uint256 marginToRelease,
        address liquidator,
        uint256 liquidatorReward,
        address insurance,
        uint256 insuranceCut
    ) external onlyMarket {
        require(marginLocked[user] >= marginToRelease, "locked");
        marginLocked[user] -= marginToRelease;
        balanceOf[user] -= marginToRelease;
        uint256 paid = liquidatorReward + insuranceCut;
        require(marginToRelease >= paid, "rewards");
        uint256 remainder = marginToRelease - paid;
        require(collateralToken.transfer(liquidator, liquidatorReward), "liq");
        if (insuranceCut > 0 && insurance != address(0)) {
            require(collateralToken.transfer(insurance, insuranceCut), "ins");
        } else if (insuranceCut > 0) {
            remainder += insuranceCut;
        }
        if (remainder > 0) {
            address to = insurance != address(0) ? insurance : liquidator;
            require(collateralToken.transfer(to, remainder), "rem");
        }
    }
}
