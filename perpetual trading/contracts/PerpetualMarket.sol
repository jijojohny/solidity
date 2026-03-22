// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPriceOracle.sol";
import "./CollateralVault.sol";

/// @title PerpetualMarket
/// @notice Oracle-priced perpetual futures with isolated margin, funding, and liquidation.
/// @dev Prices use 8 decimals (e.g. 2000e8). Size is USD notional in 1e18 fixed point (1e18 = $1).
contract PerpetualMarket {
    CollateralVault public immutable vault;
    IPriceOracle public immutable oracle;

    /// @notice Collateral is assumed 18-decimal in PnL math; adjust for 6-decimal quote in production.
    uint256 public constant USD_WAD = 1e18;

    struct Position {
        bool isLong;
        bool isOpen;
        /// @dev USD notional in 1e18 scale (1e18 = $1 notional).
        uint128 sizeUsdWad;
        uint128 entryPrice1e8;
        uint128 margin;
        int256 lastFundingIndex;
    }

    mapping(address => Position) public positions;

    uint256 public longOpenInterestWad;
    uint256 public shortOpenInterestWad;

    int256 public cumulativeFundingIndex;
    uint256 public lastFundingUpdate;

    /// @notice Max |funding| per second scaler (scaled by OI skew / total OI). Tune for your asset.
    uint256 public fundingRateScaler;

    uint256 public maintenanceMarginBps;
    uint256 public liquidationFeeBps;
    address public insuranceFund;

    address public owner;

    event PositionOpened(
        address indexed user,
        bool indexed isLong,
        uint256 sizeUsdWad,
        uint256 entryPrice1e8,
        uint256 margin
    );
    event PositionClosed(address indexed user, int256 pnl, int256 fundingPaid);
    event Liquidated(address indexed user, address indexed liquidator, uint256 reward);
    event FundingRateScalerUpdated(uint256 scaler);
    event ParamsUpdated(uint256 maintenanceBps, uint256 liqFeeBps, address insurance);

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    constructor(
        address _vault,
        address _oracle,
        uint256 _fundingRateScaler,
        uint256 _maintenanceMarginBps,
        uint256 _liquidationFeeBps,
        address _insuranceFund
    ) {
        require(_vault != address(0) && _oracle != address(0), "zero");
        vault = CollateralVault(_vault);
        oracle = IPriceOracle(_oracle);
        fundingRateScaler = _fundingRateScaler;
        maintenanceMarginBps = _maintenanceMarginBps;
        liquidationFeeBps = _liquidationFeeBps;
        insuranceFund = _insuranceFund;
        owner = msg.sender;
        lastFundingUpdate = block.timestamp;
    }

    function setFundingRateScaler(uint256 s) external onlyOwner {
        _accrueFunding();
        fundingRateScaler = s;
        emit FundingRateScalerUpdated(s);
    }

    function setParams(uint256 maintenanceBps, uint256 liqFeeBps, address _insurance) external onlyOwner {
        require(maintenanceBps < 10_000 && liqFeeBps < 10_000, "bps");
        _accrueFunding();
        maintenanceMarginBps = maintenanceBps;
        liquidationFeeBps = liqFeeBps;
        insuranceFund = _insurance;
        emit ParamsUpdated(maintenanceBps, liqFeeBps, _insurance);
    }

    function _accrueFunding() internal {
        uint256 dt = block.timestamp - lastFundingUpdate;
        if (dt == 0) return;
        uint256 totalOI = longOpenInterestWad + shortOpenInterestWad;
        if (totalOI == 0) {
            lastFundingUpdate = block.timestamp;
            return;
        }
        int256 skew = int256(longOpenInterestWad) - int256(shortOpenInterestWad);
        int256 rate = (skew * int256(fundingRateScaler)) / int256(totalOI);
        cumulativeFundingIndex += rate * int256(dt);
        lastFundingUpdate = block.timestamp;
    }

    function _markPrice() internal view returns (uint256) {
        int256 p = oracle.latestAnswer();
        require(p > 0, "bad price");
        return uint256(p);
    }

    /// @notice Long PnL in collateral wei: sizeUsdWad * (mark - entry) / entry (same dimensions as USD wad).
    function _unrealizedPnl(Position memory p, uint256 mark1e8) internal pure returns (int256) {
        if (!p.isOpen) return 0;
        int256 diff = int256(mark1e8) - int256(uint256(p.entryPrice1e8));
        return (int256(uint256(p.sizeUsdWad)) * diff) / int256(uint256(p.entryPrice1e8));
    }

    function _fundingPayment(Position memory p) internal view returns (int256) {
        if (!p.isOpen) return 0;
        int256 idxDelta = cumulativeFundingIndex - int256(p.lastFundingIndex);
        return (int256(uint256(p.sizeUsdWad)) * idxDelta) / int256(USD_WAD);
    }

    /// @dev Equity = margin + pnl - funding (long pays positive funding index growth when skew positive — sign below).
    /// Convention: positive index means longs pay; subtract from long, add to short.
    function _equity(Position memory p, uint256 mark1e8) internal view returns (int256) {
        int256 upnl = _unrealizedPnl(p, mark1e8);
        int256 fund = _fundingPayment(p);
        int256 m = int256(uint256(p.margin));
        if (p.isLong) return m + upnl - fund;
        return m - upnl + fund;
    }

    function _notionalAtMark(Position memory p, uint256 mark1e8) internal pure returns (uint256) {
        return (uint256(p.sizeUsdWad) * mark1e8) / uint256(p.entryPrice1e8);
    }

    function openPosition(bool isLong, uint128 sizeUsdWad, uint128 marginAmount) external {
        require(sizeUsdWad > 0 && marginAmount > 0, "amount");
        require(!positions[msg.sender].isOpen, "already open");
        _accrueFunding();

        uint256 mark = _markPrice();
        vault.lockMargin(msg.sender, marginAmount);

        positions[msg.sender] = Position({
            isLong: isLong,
            isOpen: true,
            sizeUsdWad: sizeUsdWad,
            entryPrice1e8: uint128(mark),
            margin: marginAmount,
            lastFundingIndex: cumulativeFundingIndex
        });

        if (isLong) longOpenInterestWad += uint256(sizeUsdWad);
        else shortOpenInterestWad += uint256(sizeUsdWad);

        emit PositionOpened(msg.sender, isLong, sizeUsdWad, mark, marginAmount);
    }

    function addMargin(uint128 amount) external {
        Position storage p = positions[msg.sender];
        require(p.isOpen, "no position");
        _accrueFunding();
        vault.lockMargin(msg.sender, amount);
        p.margin += amount;
    }

    function closePosition() external {
        Position storage p = positions[msg.sender];
        require(p.isOpen, "no position");
        _accrueFunding();

        uint256 mark = _markPrice();
        Position memory pm = p;

        int256 upnl = _unrealizedPnl(pm, mark);
        int256 fund = _fundingPayment(pm);
        int256 pnl;
        if (pm.isLong) pnl = upnl - fund;
        else pnl = -upnl + fund;

        if (pm.isLong) longOpenInterestWad -= uint256(pm.sizeUsdWad);
        else shortOpenInterestWad -= uint256(pm.sizeUsdWad);

        delete positions[msg.sender];

        vault.unlockAndCredit(msg.sender, pm.margin, pnl);
        emit PositionClosed(msg.sender, upnl, fund);
    }

    function liquidate(address user) external {
        Position storage p = positions[user];
        require(p.isOpen, "no position");
        _accrueFunding();

        uint256 mark = _markPrice();
        Position memory pm = p;

        int256 eq = _equity(pm, mark);
        uint256 notional = _notionalAtMark(pm, mark);
        require(notional > 0, "notional");
        require(eq * 10000 < int256(maintenanceMarginBps * notional), "healthy");

        uint256 marginAmt = uint256(pm.margin);
        uint256 liqReward = (marginAmt * liquidationFeeBps) / 10000;
        uint256 insCut = insuranceFund != address(0) ? (marginAmt * 500) / 10000 : 0;

        if (pm.isLong) longOpenInterestWad -= uint256(pm.sizeUsdWad);
        else shortOpenInterestWad -= uint256(pm.sizeUsdWad);

        delete positions[user];

        vault.seizeAndPay(user, marginAmt, msg.sender, liqReward, insuranceFund, insCut);
        emit Liquidated(user, msg.sender, liqReward);
    }

    function getPosition(address user)
        external
        view
        returns (
            bool open,
            bool isLong,
            uint256 sizeUsdWad,
            uint256 entryPrice1e8,
            uint256 margin,
            int256 unrealizedPnl,
            int256 fundingPending,
            int256 equity
        )
    {
        Position memory p = positions[user];
        if (!p.isOpen) return (false, false, 0, 0, 0, 0, 0, 0);
        uint256 mark = _markPrice();
        int256 upnl = _unrealizedPnl(p, mark);
        int256 fund = _fundingPayment(p);
        int256 eq = _equity(p, mark);
        return (true, p.isLong, p.sizeUsdWad, p.entryPrice1e8, p.margin, upnl, fund, eq);
    }
}
