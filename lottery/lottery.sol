// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Lottery
 * @dev A decentralized lottery contract with multiple rounds, random winner selection, and secure prize distribution
 * 
 * Features:
 * - Players enter by paying an entry fee
 * - Manager controls lottery rounds (start/end)
 * - Random winner selection using block difficulty and timestamp
 * - Automatic prize distribution
 * - Multiple lottery rounds support
 * - Reentrancy protection
 * - Events for transparency
 */
contract Lottery {
    // State variables
    address public manager;
    uint256 public entryFee;
    uint256 public currentRound;
    bool public lotteryActive;
    
    // Round tracking
    struct Round {
        uint256 roundNumber;
        address[] players;
        address winner;
        uint256 prizePool;
        uint256 startTime;
        uint256 endTime;
        bool completed;
    }
    
    mapping(uint256 => Round) public rounds;
    mapping(address => uint256) public playerWinnings;
    
    // Events
    event LotteryStarted(uint256 indexed roundNumber, uint256 entryFee);
    event PlayerEntered(uint256 indexed roundNumber, address indexed player, uint256 entryFee);
    event LotteryEnded(uint256 indexed roundNumber, address indexed winner, uint256 prize);
    event PrizeDistributed(address indexed winner, uint256 amount);
    event EntryFeeChanged(uint256 oldFee, uint256 newFee);
    
    // Modifiers
    modifier onlyManager() {
        require(msg.sender == manager, "Only manager can call this function");
        _;
    }
    
    modifier lotteryMustBeActive() {
        require(lotteryActive, "Lottery is not active");
        _;
    }
    
    modifier lotteryMustBeInactive() {
        require(!lotteryActive, "Lottery is already active");
        _;
    }
    
    modifier validEntryFee() {
        require(msg.value >= entryFee, "Insufficient entry fee");
        _;
    }
    
    /**
     * @dev Constructor
     * @param _entryFee Minimum entry fee in wei
     */
    constructor(uint256 _entryFee) {
        require(_entryFee > 0, "Entry fee must be greater than 0");
        manager = msg.sender;
        entryFee = _entryFee;
        currentRound = 0;
        lotteryActive = false;
    }
    
    /**
     * @dev Start a new lottery round
     */
    function startLottery() public onlyManager lotteryMustBeInactive {
        currentRound++;
        lotteryActive = true;
        
        rounds[currentRound] = Round({
            roundNumber: currentRound,
            players: new address[](0),
            winner: address(0),
            prizePool: 0,
            startTime: block.timestamp,
            endTime: 0,
            completed: false
        });
        
        emit LotteryStarted(currentRound, entryFee);
    }
    
    /**
     * @dev Enter the current lottery round
     */
    function enter() public payable lotteryMustBeActive validEntryFee {
        require(msg.sender != manager, "Manager cannot enter the lottery");
        
        Round storage round = rounds[currentRound];
        round.players.push(msg.sender);
        round.prizePool += msg.value;
        
        // Refund excess payment
        if (msg.value > entryFee) {
            payable(msg.sender).transfer(msg.value - entryFee);
            round.prizePool -= (msg.value - entryFee);
        }
        
        emit PlayerEntered(currentRound, msg.sender, entryFee);
    }
    
    /**
     * @dev End the current lottery and select a winner
     */
    function endLottery() public onlyManager lotteryMustBeActive {
        Round storage round = rounds[currentRound];
        require(round.players.length > 0, "No players in the lottery");
        
        lotteryActive = false;
        round.endTime = block.timestamp;
        
        // Select random winner
        uint256 randomIndex = _generateRandomNumber(round.players.length) % round.players.length;
        address winner = round.players[randomIndex];
        round.winner = winner;
        round.completed = true;
        
        // Distribute prize
        uint256 prize = round.prizePool;
        playerWinnings[winner] += prize;
        payable(winner).transfer(prize);
        
        emit LotteryEnded(currentRound, winner, prize);
        emit PrizeDistributed(winner, prize);
    }
    
    /**
     * @dev Generate a pseudo-random number
     * @param _playerCount Number of players in the lottery
     * @return A random number based on block properties
     * 
     * Note: This uses block properties for randomness. For production use,
     * consider using Chainlink VRF for verifiable randomness.
     */
    function _generateRandomNumber(uint256 _playerCount) private view returns (uint256) {
        // Use blockhash, timestamp, and other block properties for randomness
        // Note: blockhash only works for the last 256 blocks
        uint256 blockHash = 0;
        if (block.number > 0) {
            blockHash = uint256(blockhash(block.number - 1));
        }
        
        return uint256(keccak256(abi.encodePacked(
            blockHash,
            block.timestamp,
            block.number,
            _playerCount,
            msg.sender,
            address(this)
        )));
    }
    
    /**
     * @dev Get the list of players in the current round
     * @return Array of player addresses
     */
    function getPlayers() public view returns (address[] memory) {
        return rounds[currentRound].players;
    }
    
    /**
     * @dev Get the number of players in the current round
     * @return Number of players
     */
    function getPlayerCount() public view returns (uint256) {
        return rounds[currentRound].players.length;
    }
    
    /**
     * @dev Get the prize pool for the current round
     * @return Prize pool amount in wei
     */
    function getPrizePool() public view returns (uint256) {
        return rounds[currentRound].prizePool;
    }
    
    /**
     * @dev Get round information
     * @param _roundNumber Round number to query
     * @return Round struct data
     */
    function getRound(uint256 _roundNumber) public view returns (
        uint256 roundNumber,
        address[] memory players,
        address winner,
        uint256 prizePool,
        uint256 startTime,
        uint256 endTime,
        bool completed
    ) {
        Round memory round = rounds[_roundNumber];
        return (
            round.roundNumber,
            round.players,
            round.winner,
            round.prizePool,
            round.startTime,
            round.endTime,
            round.completed
        );
    }
    
    /**
     * @dev Get total winnings for a player
     * @param _player Address of the player
     * @return Total winnings in wei
     */
    function getPlayerWinnings(address _player) public view returns (uint256) {
        return playerWinnings[_player];
    }
    
    /**
     * @dev Update the entry fee (only manager)
     * @param _newEntryFee New entry fee in wei
     */
    function setEntryFee(uint256 _newEntryFee) public onlyManager {
        require(_newEntryFee > 0, "Entry fee must be greater than 0");
        require(!lotteryActive, "Cannot change fee while lottery is active");
        
        uint256 oldFee = entryFee;
        entryFee = _newEntryFee;
        
        emit EntryFeeChanged(oldFee, _newEntryFee);
    }
    
    /**
     * @dev Get contract balance
     * @return Contract balance in wei
     */
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev Emergency withdrawal (only manager, only if no active lottery)
     * @param _amount Amount to withdraw in wei
     */
    function emergencyWithdraw(uint256 _amount) public onlyManager {
        require(!lotteryActive, "Cannot withdraw while lottery is active");
        require(_amount <= address(this).balance, "Insufficient balance");
        
        payable(manager).transfer(_amount);
    }
    
    /**
     * @dev Transfer manager role to a new address
     * @param _newManager Address of the new manager
     */
    function transferManager(address _newManager) public onlyManager {
        require(_newManager != address(0), "Invalid manager address");
        manager = _newManager;
    }
    
    /**
     * @dev Check if an address is a player in the current round
     * @param _player Address to check
     * @return True if player is in current round
     */
    function isPlayer(address _player) public view returns (bool) {
        address[] memory players = rounds[currentRound].players;
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == _player) {
                return true;
            }
        }
        return false;
    }
}
