// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IERC20.sol";
import "./interfaces/IAaveLendingPool.sol";

/**
 * @title NoLossLottery
 * @dev A no-loss lottery where participants deposit tokens, earn yield through Aave,
 * and only the yield is distributed as prizes. Participants can withdraw their
 * full principal at any time.
 *
 * How it works:
 * 1. Users deposit tokens (e.g., DAI, USDC)
 * 2. Deposits are supplied to Aave to earn yield
 * 3. At the end of each round, accrued yield becomes the prize
 * 4. A random winner receives the yield prize
 * 5. All participants can withdraw their original deposit anytime
 *
 * Features:
 * - No loss of principal - users always get their deposit back
 * - Yield generation through Aave lending protocol
 * - Fair random winner selection (Chainlink VRF recommended for production)
 * - Multiple deposit rounds support
 * - Proportional winning chances based on deposit amount
 * - Emergency withdrawal mechanism
 */
contract NoLossLottery {
    // Structs
    struct Player {
        uint256 depositAmount;
        uint256 depositTimestamp;
        uint256 lastRoundClaimed;
        bool isActive;
    }

    struct Round {
        uint256 roundNumber;
        uint256 startTime;
        uint256 endTime;
        uint256 totalDeposits;
        uint256 yieldGenerated;
        address winner;
        bool completed;
        bool prizeClaimed;
    }

    // State variables
    address public owner;
    IERC20 public depositToken;
    IERC20 public aToken;
    IAaveLendingPool public aaveLendingPool;

    uint256 public currentRound;
    uint256 public roundDuration;
    uint256 public minimumDeposit;
    uint256 public totalDeposits;
    uint256 public playerCount;

    bool public paused;

    // Mappings
    mapping(address => Player) public players;
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => address[]) public roundParticipants;
    mapping(address => uint256) public unclaimedPrizes;

    // Events
    event Deposited(address indexed player, uint256 amount, uint256 round);
    event Withdrawn(address indexed player, uint256 amount);
    event RoundStarted(uint256 indexed roundNumber, uint256 startTime, uint256 endTime);
    event RoundEnded(uint256 indexed roundNumber, address indexed winner, uint256 prize);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event YieldHarvested(uint256 indexed roundNumber, uint256 yieldAmount);
    event EmergencyWithdrawal(address indexed player, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "NoLossLottery: caller is not the owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "NoLossLottery: contract is paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "NoLossLottery: contract is not paused");
        _;
    }

    modifier roundActive() {
        require(currentRound > 0, "NoLossLottery: no active round");
        require(!rounds[currentRound].completed, "NoLossLottery: round already completed");
        _;
    }

    /**
     * @dev Constructor
     * @param _depositToken Address of the token to deposit (e.g., DAI)
     * @param _aToken Address of the corresponding aToken (e.g., aDAI)
     * @param _aaveLendingPool Address of the Aave lending pool
     * @param _roundDuration Duration of each lottery round in seconds
     * @param _minimumDeposit Minimum deposit amount
     */
    constructor(
        address _depositToken,
        address _aToken,
        address _aaveLendingPool,
        uint256 _roundDuration,
        uint256 _minimumDeposit
    ) {
        require(_depositToken != address(0), "NoLossLottery: invalid deposit token");
        require(_aToken != address(0), "NoLossLottery: invalid aToken");
        require(_aaveLendingPool != address(0), "NoLossLottery: invalid lending pool");
        require(_roundDuration > 0, "NoLossLottery: invalid round duration");
        require(_minimumDeposit > 0, "NoLossLottery: invalid minimum deposit");

        owner = msg.sender;
        depositToken = IERC20(_depositToken);
        aToken = IERC20(_aToken);
        aaveLendingPool = IAaveLendingPool(_aaveLendingPool);
        roundDuration = _roundDuration;
        minimumDeposit = _minimumDeposit;
        currentRound = 0;
        paused = false;
    }

    /**
     * @dev Start a new lottery round
     */
    function startRound() external onlyOwner whenNotPaused {
        if (currentRound > 0) {
            require(rounds[currentRound].completed, "NoLossLottery: previous round not completed");
        }

        currentRound++;

        rounds[currentRound] = Round({
            roundNumber: currentRound,
            startTime: block.timestamp,
            endTime: block.timestamp + roundDuration,
            totalDeposits: totalDeposits,
            yieldGenerated: 0,
            winner: address(0),
            completed: false,
            prizeClaimed: false
        });

        emit RoundStarted(currentRound, block.timestamp, block.timestamp + roundDuration);
    }

    /**
     * @dev Deposit tokens into the lottery
     * @param _amount Amount of tokens to deposit
     */
    function deposit(uint256 _amount) external whenNotPaused roundActive {
        require(_amount >= minimumDeposit, "NoLossLottery: amount below minimum");
        require(block.timestamp < rounds[currentRound].endTime, "NoLossLottery: round has ended");

        Player storage player = players[msg.sender];

        // Transfer tokens from user
        require(
            depositToken.transferFrom(msg.sender, address(this), _amount),
            "NoLossLottery: transfer failed"
        );

        // Approve and supply to Aave
        depositToken.approve(address(aaveLendingPool), _amount);
        aaveLendingPool.supply(address(depositToken), _amount, address(this), 0);

        // Update player state
        if (!player.isActive) {
            player.isActive = true;
            player.depositTimestamp = block.timestamp;
            player.lastRoundClaimed = currentRound - 1;
            playerCount++;
            roundParticipants[currentRound].push(msg.sender);
        }

        player.depositAmount += _amount;
        totalDeposits += _amount;
        rounds[currentRound].totalDeposits = totalDeposits;

        emit Deposited(msg.sender, _amount, currentRound);
    }

    /**
     * @dev Withdraw deposited tokens (principal only)
     * @param _amount Amount to withdraw
     */
    function withdraw(uint256 _amount) external whenNotPaused {
        Player storage player = players[msg.sender];
        require(player.isActive, "NoLossLottery: no active deposit");
        require(_amount > 0, "NoLossLottery: invalid amount");
        require(_amount <= player.depositAmount, "NoLossLottery: insufficient balance");

        // Withdraw from Aave
        aaveLendingPool.withdraw(address(depositToken), _amount, address(this));

        // Update state
        player.depositAmount -= _amount;
        totalDeposits -= _amount;

        if (player.depositAmount == 0) {
            player.isActive = false;
            playerCount--;
        }

        // Transfer tokens back to user
        require(
            depositToken.transfer(msg.sender, _amount),
            "NoLossLottery: transfer failed"
        );

        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @dev End the current round and select a winner
     */
    function endRound() external onlyOwner {
        Round storage round = rounds[currentRound];
        require(currentRound > 0, "NoLossLottery: no active round");
        require(!round.completed, "NoLossLottery: round already completed");
        require(block.timestamp >= round.endTime, "NoLossLottery: round not yet ended");

        // Calculate yield generated
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        uint256 yieldGenerated = 0;

        if (aTokenBalance > totalDeposits) {
            yieldGenerated = aTokenBalance - totalDeposits;
        }

        round.yieldGenerated = yieldGenerated;

        // Select winner if there's yield and participants
        if (yieldGenerated > 0 && roundParticipants[currentRound].length > 0) {
            address winner = _selectWinner(currentRound);
            round.winner = winner;
            unclaimedPrizes[winner] += yieldGenerated;

            // Withdraw yield from Aave
            if (yieldGenerated > 0) {
                aaveLendingPool.withdraw(address(depositToken), yieldGenerated, address(this));
            }

            emit YieldHarvested(currentRound, yieldGenerated);
        }

        round.completed = true;
        emit RoundEnded(currentRound, round.winner, yieldGenerated);
    }

    /**
     * @dev Claim accumulated prizes
     */
    function claimPrize() external whenNotPaused {
        uint256 prize = unclaimedPrizes[msg.sender];
        require(prize > 0, "NoLossLottery: no prize to claim");

        unclaimedPrizes[msg.sender] = 0;

        require(
            depositToken.transfer(msg.sender, prize),
            "NoLossLottery: transfer failed"
        );

        emit PrizeClaimed(msg.sender, prize);
    }

    /**
     * @dev Select a winner based on deposit amounts (weighted random)
     * @param _roundNumber Round number
     * @return winner Address of the selected winner
     */
    function _selectWinner(uint256 _roundNumber) internal view returns (address winner) {
        address[] memory participants = roundParticipants[_roundNumber];
        require(participants.length > 0, "NoLossLottery: no participants");

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < participants.length; i++) {
            totalWeight += players[participants[i]].depositAmount;
        }

        uint256 randomNumber = _generateRandomNumber(totalWeight);
        uint256 cumulativeWeight = 0;

        for (uint256 i = 0; i < participants.length; i++) {
            cumulativeWeight += players[participants[i]].depositAmount;
            if (randomNumber < cumulativeWeight) {
                return participants[i];
            }
        }

        return participants[participants.length - 1];
    }

    /**
     * @dev Generate pseudo-random number
     * @param _max Maximum value
     * @return Random number
     * @notice For production, use Chainlink VRF for verifiable randomness
     */
    function _generateRandomNumber(uint256 _max) internal view returns (uint256) {
        return uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    block.prevrandao,
                    totalDeposits,
                    playerCount
                )
            )
        ) % _max;
    }

    // View functions

    /**
     * @dev Get player information
     * @param _player Player address
     */
    function getPlayerInfo(address _player) external view returns (
        uint256 depositAmount,
        uint256 depositTimestamp,
        uint256 lastRoundClaimed,
        bool isActive,
        uint256 pendingPrize
    ) {
        Player memory player = players[_player];
        return (
            player.depositAmount,
            player.depositTimestamp,
            player.lastRoundClaimed,
            player.isActive,
            unclaimedPrizes[_player]
        );
    }

    /**
     * @dev Get round information
     * @param _roundNumber Round number
     */
    function getRoundInfo(uint256 _roundNumber) external view returns (
        uint256 roundNumber,
        uint256 startTime,
        uint256 endTime,
        uint256 roundTotalDeposits,
        uint256 yieldGenerated,
        address winner,
        bool completed,
        uint256 participantCount
    ) {
        Round memory round = rounds[_roundNumber];
        return (
            round.roundNumber,
            round.startTime,
            round.endTime,
            round.totalDeposits,
            round.yieldGenerated,
            round.winner,
            round.completed,
            roundParticipants[_roundNumber].length
        );
    }

    /**
     * @dev Get current yield accrued
     */
    function getCurrentYield() external view returns (uint256) {
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        if (aTokenBalance > totalDeposits) {
            return aTokenBalance - totalDeposits;
        }
        return 0;
    }

    /**
     * @dev Get round participants
     * @param _roundNumber Round number
     */
    function getRoundParticipants(uint256 _roundNumber) external view returns (address[] memory) {
        return roundParticipants[_roundNumber];
    }

    /**
     * @dev Get player's winning probability for current round
     * @param _player Player address
     */
    function getWinningProbability(address _player) external view returns (uint256 numerator, uint256 denominator) {
        if (totalDeposits == 0 || !players[_player].isActive) {
            return (0, 1);
        }
        return (players[_player].depositAmount, totalDeposits);
    }

    /**
     * @dev Check if round can be ended
     */
    function canEndRound() external view returns (bool) {
        if (currentRound == 0) return false;
        Round memory round = rounds[currentRound];
        return !round.completed && block.timestamp >= round.endTime;
    }

    /**
     * @dev Get time remaining in current round
     */
    function getTimeRemaining() external view returns (uint256) {
        if (currentRound == 0) return 0;
        Round memory round = rounds[currentRound];
        if (round.completed || block.timestamp >= round.endTime) return 0;
        return round.endTime - block.timestamp;
    }

    // Admin functions

    /**
     * @dev Update round duration
     * @param _newDuration New round duration in seconds
     */
    function setRoundDuration(uint256 _newDuration) external onlyOwner {
        require(_newDuration > 0, "NoLossLottery: invalid duration");
        roundDuration = _newDuration;
    }

    /**
     * @dev Update minimum deposit
     * @param _newMinimum New minimum deposit
     */
    function setMinimumDeposit(uint256 _newMinimum) external onlyOwner {
        require(_newMinimum > 0, "NoLossLottery: invalid minimum");
        minimumDeposit = _newMinimum;
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner whenNotPaused {
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner whenPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Transfer ownership
     * @param _newOwner New owner address
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "NoLossLottery: invalid address");
        address oldOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(oldOwner, _newOwner);
    }

    /**
     * @dev Emergency withdrawal for users when contract is paused
     */
    function emergencyWithdraw() external whenPaused {
        Player storage player = players[msg.sender];
        require(player.isActive, "NoLossLottery: no active deposit");

        uint256 amount = player.depositAmount;
        player.depositAmount = 0;
        player.isActive = false;
        totalDeposits -= amount;
        playerCount--;

        // Withdraw from Aave
        aaveLendingPool.withdraw(address(depositToken), amount, msg.sender);

        emit EmergencyWithdrawal(msg.sender, amount);
    }

    /**
     * @dev Rescue stuck tokens (not deposit or aToken)
     * @param _token Token address
     * @param _amount Amount to rescue
     */
    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        require(_token != address(depositToken), "NoLossLottery: cannot rescue deposit token");
        require(_token != address(aToken), "NoLossLottery: cannot rescue aToken");
        IERC20(_token).transfer(owner, _amount);
    }
}
