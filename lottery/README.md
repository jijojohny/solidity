# Lottery Smart Contract

A decentralized lottery smart contract built on Ethereum with multiple rounds, random winner selection, and secure prize distribution.

## Features

- 🎰 **Multiple Lottery Rounds**: Support for multiple independent lottery rounds
- 🎲 **Random Winner Selection**: Pseudo-random winner selection using block properties
- 💰 **Automatic Prize Distribution**: Winners receive prizes automatically
- 🔒 **Security Features**: Reentrancy protection, access control, and input validation
- 📊 **Transparency**: All events are logged on-chain
- 👤 **Manager Controls**: Owner can start/end lotteries and manage settings
- 📈 **Player Tracking**: Track winnings and participation history

## Contract Functions

### Public Functions

#### `enter()`
Enter the current lottery round by paying the entry fee.
- **Requirements**: 
  - Lottery must be active
  - Must send at least the entry fee
  - Manager cannot enter
- **Payable**: Yes (must send >= entryFee)

#### `getPlayers()`
Get the list of all players in the current round.
- **Returns**: Array of player addresses

#### `getPlayerCount()`
Get the number of players in the current round.
- **Returns**: Number of players (uint256)

#### `getPrizePool()`
Get the current prize pool amount.
- **Returns**: Prize pool in wei (uint256)

#### `getRound(uint256 _roundNumber)`
Get complete information about a specific round.
- **Returns**: Round struct with all round data

#### `getPlayerWinnings(address _player)`
Get total winnings for a specific player across all rounds.
- **Returns**: Total winnings in wei

#### `getBalance()`
Get the contract's current balance.
- **Returns**: Contract balance in wei

#### `isPlayer(address _player)`
Check if an address is a player in the current round.
- **Returns**: True if player is in current round

### Manager-Only Functions

#### `startLottery()`
Start a new lottery round.
- **Requirements**: 
  - Only manager can call
  - Lottery must be inactive

#### `endLottery()`
End the current lottery, select a winner, and distribute the prize.
- **Requirements**: 
  - Only manager can call
  - Lottery must be active
  - At least one player must be in the lottery

#### `setEntryFee(uint256 _newEntryFee)`
Update the entry fee for future lottery rounds.
- **Requirements**: 
  - Only manager can call
  - Lottery must be inactive
  - New fee must be greater than 0

#### `emergencyWithdraw(uint256 _amount)`
Emergency withdrawal function (only when lottery is inactive).
- **Requirements**: 
  - Only manager can call
  - Lottery must be inactive

#### `transferManager(address _newManager)`
Transfer manager role to a new address.
- **Requirements**: Only current manager can call

## Deployment

### Constructor Parameters

- `_entryFee`: Minimum entry fee in wei (e.g., 1000000000000000000 for 1 ETH)

### Example Deployment (Remix)

1. Compile the contract with Solidity 0.8.0 or higher
2. Deploy with constructor parameter:
   - Entry Fee: `1000000000000000000` (1 ETH in wei)
3. The deployer becomes the manager

## Usage Flow

### 1. Start a Lottery Round

```solidity
// Manager calls
lottery.startLottery();
```

### 2. Players Enter

```solidity
// Players send ETH (at least entryFee) to enter
lottery.enter{value: entryFee}();
```

### 3. End Lottery and Select Winner

```solidity
// Manager calls when ready
lottery.endLottery();
// Winner is automatically selected and prize is distributed
```

### 4. Start Next Round

```solidity
// Manager can start a new round
lottery.startLottery();
```

## Events

- `LotteryStarted(uint256 indexed roundNumber, uint256 entryFee)`
- `PlayerEntered(uint256 indexed roundNumber, address indexed player, uint256 entryFee)`
- `LotteryEnded(uint256 indexed roundNumber, address indexed winner, uint256 prize)`
- `PrizeDistributed(address indexed winner, uint256 amount)`
- `EntryFeeChanged(uint256 oldFee, uint256 newFee)`

## Security Considerations

⚠️ **Important Notes:**

1. **Randomness**: The contract uses block properties for randomness, which is not truly random and can be manipulated by miners. For production use, consider:
   - Chainlink VRF (Verifiable Random Function)
   - Commit-Reveal schemes
   - Oracle-based randomness

2. **Entry Fee**: Excess payment is automatically refunded, but players should send exactly the entry fee to avoid gas waste.

3. **Manager Role**: The manager has significant control. Consider using a multi-sig wallet or DAO for production.

4. **Reentrancy**: The contract uses the Checks-Effects-Interactions pattern to prevent reentrancy attacks.

## Example Interaction (JavaScript/ethers.js)

```javascript
const lottery = new ethers.Contract(contractAddress, abi, signer);

// Start lottery (manager only)
await lottery.startLottery();

// Enter lottery
await lottery.enter({ value: ethers.utils.parseEther("1.0") });

// Check players
const players = await lottery.getPlayers();
console.log("Players:", players);

// Check prize pool
const prizePool = await lottery.getPrizePool();
console.log("Prize Pool:", ethers.utils.formatEther(prizePool));

// End lottery (manager only)
await lottery.endLottery();

// Check winner
const round = await lottery.getRound(1);
console.log("Winner:", round.winner);
```

## Testing

Before deploying to mainnet, thoroughly test:
- Entry fee validation
- Winner selection
- Prize distribution
- Multiple rounds
- Manager access control
- Edge cases (no players, etc.)

## License

MIT
