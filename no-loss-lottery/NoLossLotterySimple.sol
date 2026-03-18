// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title NoLossLotterySimple
 * @dev A simplified no-loss lottery using native ETH with manual yield injection
 * 
 * This is a standalone version that doesn't require external DeFi protocols.
 * The owner/sponsor can inject yield which becomes the prize pool.
 * Participants never lose their deposited ETH.
 *
 * Use cases:
 * - Testing and learning
 * - Sponsored lotteries where a sponsor provides the prizes
 * - Situations where external DeFi integration isn't available
 *
 * Features:
 * - ETH deposits (no external token dependencies)
 * - Manual yield injection by sponsor/owner
 * - Fair weighted random selection
 * - Full principal withdrawal anytime
 * - Multiple round support
 */
contract NoLossLotterySimple {
    struct Player {
        uint256 balance;
        uint256 depositTime;
        bool isParticipant;
    }

    struct LotteryRound {
        uint256 roundId;
        uint256 startTime;
        uint256 endTime;
        uint256 prizePool;
        uint256 totalDepositsAtEnd;
        address winner;
        bool isComplete;
        bool prizeDistributed;
    }

    address public owner;
    uint256 public currentRound;
    uint256 public roundDuration;
    uint256 public minimumDeposit;
    uint256 public totalDeposits;
    uint256 public accumulatedYield;

    address[] public participants;
    mapping(address => Player) public players;
    mapping(uint256 => LotteryRound) public rounds;
    mapping(address => uint256) public pendingWinnings;
    mapping(address => uint256) private participantIndex;
    mapping(address => bool) private isInParticipantList;

    event Deposited(address indexed player, uint256 amount);
    event Withdrawn(address indexed player, uint256 amount);
    event YieldAdded(address indexed sponsor, uint256 amount);
    event RoundStarted(uint256 indexed roundId, uint256 endTime);
    event RoundCompleted(uint256 indexed roundId, address indexed winner, uint256 prize);
    event WinningsClaimed(address indexed winner, uint256 amount);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    modifier hasActiveDeposit() {
        require(players[msg.sender].balance > 0, "No active deposit");
        _;
    }

    constructor(uint256 _roundDuration, uint256 _minimumDeposit) {
        require(_roundDuration > 0, "Invalid round duration");
        require(_minimumDeposit > 0, "Invalid minimum deposit");

        owner = msg.sender;
        roundDuration = _roundDuration;
        minimumDeposit = _minimumDeposit;
    }

    /**
     * @dev Start a new lottery round
     */
    function startRound() external onlyOwner {
        if (currentRound > 0) {
            require(rounds[currentRound].isComplete, "Current round not complete");
        }

        currentRound++;

        rounds[currentRound] = LotteryRound({
            roundId: currentRound,
            startTime: block.timestamp,
            endTime: block.timestamp + roundDuration,
            prizePool: 0,
            totalDepositsAtEnd: 0,
            winner: address(0),
            isComplete: false,
            prizeDistributed: false
        });

        emit RoundStarted(currentRound, block.timestamp + roundDuration);
    }

    /**
     * @dev Deposit ETH to participate in the lottery
     */
    function deposit() external payable {
        require(currentRound > 0, "No active round");
        require(!rounds[currentRound].isComplete, "Round is complete");
        require(msg.value >= minimumDeposit, "Below minimum deposit");

        Player storage player = players[msg.sender];

        if (!isInParticipantList[msg.sender]) {
            participantIndex[msg.sender] = participants.length;
            participants.push(msg.sender);
            isInParticipantList[msg.sender] = true;
            player.isParticipant = true;
            player.depositTime = block.timestamp;
        }

        player.balance += msg.value;
        totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @dev Withdraw deposited ETH (principal only)
     * @param _amount Amount to withdraw
     */
    function withdraw(uint256 _amount) external hasActiveDeposit {
        Player storage player = players[msg.sender];
        require(_amount > 0 && _amount <= player.balance, "Invalid amount");

        player.balance -= _amount;
        totalDeposits -= _amount;

        if (player.balance == 0) {
            player.isParticipant = false;
            _removeParticipant(msg.sender);
        }

        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @dev Add yield to the prize pool (sponsor function)
     */
    function addYield() external payable {
        require(msg.value > 0, "Must send ETH");
        accumulatedYield += msg.value;
        emit YieldAdded(msg.sender, msg.value);
    }

    /**
     * @dev Complete the current round and select a winner
     */
    function completeRound() external onlyOwner {
        require(currentRound > 0, "No active round");
        LotteryRound storage round = rounds[currentRound];
        require(!round.isComplete, "Round already complete");
        require(block.timestamp >= round.endTime, "Round not ended");

        round.isComplete = true;
        round.totalDepositsAtEnd = totalDeposits;
        round.prizePool = accumulatedYield;

        if (participants.length > 0 && accumulatedYield > 0) {
            address winner = _selectWeightedWinner();
            round.winner = winner;
            pendingWinnings[winner] += accumulatedYield;
            accumulatedYield = 0;

            emit RoundCompleted(currentRound, winner, round.prizePool);
        } else {
            emit RoundCompleted(currentRound, address(0), 0);
        }
    }

    /**
     * @dev Claim pending winnings
     */
    function claimWinnings() external {
        uint256 amount = pendingWinnings[msg.sender];
        require(amount > 0, "No winnings to claim");

        pendingWinnings[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        emit WinningsClaimed(msg.sender, amount);
    }

    /**
     * @dev Select winner weighted by deposit amount
     */
    function _selectWeightedWinner() internal view returns (address) {
        require(participants.length > 0, "No participants");
        require(totalDeposits > 0, "No deposits");

        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    block.prevrandao,
                    participants.length,
                    totalDeposits
                )
            )
        ) % totalDeposits;

        uint256 cumulative = 0;
        for (uint256 i = 0; i < participants.length; i++) {
            cumulative += players[participants[i]].balance;
            if (random < cumulative) {
                return participants[i];
            }
        }

        return participants[participants.length - 1];
    }

    /**
     * @dev Remove participant from array
     */
    function _removeParticipant(address _participant) internal {
        if (!isInParticipantList[_participant]) return;

        uint256 index = participantIndex[_participant];
        uint256 lastIndex = participants.length - 1;

        if (index != lastIndex) {
            address lastParticipant = participants[lastIndex];
            participants[index] = lastParticipant;
            participantIndex[lastParticipant] = index;
        }

        participants.pop();
        delete participantIndex[_participant];
        isInParticipantList[_participant] = false;
    }

    // View functions

    function getParticipantCount() external view returns (uint256) {
        return participants.length;
    }

    function getParticipants() external view returns (address[] memory) {
        return participants;
    }

    function getPlayerBalance(address _player) external view returns (uint256) {
        return players[_player].balance;
    }

    function getRoundInfo(uint256 _roundId) external view returns (
        uint256 startTime,
        uint256 endTime,
        uint256 prizePool,
        address winner,
        bool isComplete
    ) {
        LotteryRound memory round = rounds[_roundId];
        return (
            round.startTime,
            round.endTime,
            round.prizePool,
            round.winner,
            round.isComplete
        );
    }

    function getTimeRemaining() external view returns (uint256) {
        if (currentRound == 0) return 0;
        LotteryRound memory round = rounds[currentRound];
        if (round.isComplete || block.timestamp >= round.endTime) return 0;
        return round.endTime - block.timestamp;
    }

    function getWinProbability(address _player) external view returns (uint256 numerator, uint256 denominator) {
        if (totalDeposits == 0) return (0, 1);
        return (players[_player].balance, totalDeposits);
    }

    function getCurrentPrizePool() external view returns (uint256) {
        return accumulatedYield;
    }

    // Admin functions

    function setRoundDuration(uint256 _duration) external onlyOwner {
        require(_duration > 0, "Invalid duration");
        roundDuration = _duration;
    }

    function setMinimumDeposit(uint256 _minimum) external onlyOwner {
        require(_minimum > 0, "Invalid minimum");
        minimumDeposit = _minimum;
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        address oldOwner = owner;
        owner = _newOwner;
        emit OwnerChanged(oldOwner, _newOwner);
    }

    receive() external payable {
        accumulatedYield += msg.value;
        emit YieldAdded(msg.sender, msg.value);
    }
}
