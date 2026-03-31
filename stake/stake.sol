//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SimpleStaking is ReentrancyGuard{
    IERC20 public stakingToken;
    IERC20 public rewardToken;

    uint256 public rewardRate;

    struct StakeInfo{
        uint256 amount;
        uint256 lastUpdated;
        uint256 rewards;
    }

    mapping(address=> StakeInfo) public stakes;

    constructor(address _stakingToken, address _rewardToken, uint256 _rewardRate){
        stakingToken = IERC20(_stakingToken);
        rewardToken =   IERC20(_rewardToken);
        rewardRate = _rewardRate;
    }

    function stake(uint256 amount) external nonReentrant{
        require(amount > 0 , "Amount must be >  ");
        StakeInfo storage user = stakes[msg.sender];
        _updateRewards(msg.sender);
        stakingToken.transferFrom(msg.sender, address(this), amount);
        user.amount += amount;
    }

    function withdraw(uint256 amount) external nonReentrant{
        StakeInfo storage user = stakes[msg.sender];
        require(user.amount>= amount, "Not enough staked");

        _updateRewards(msg.sender);

        user.amount -= amount;
        stakingToken.transfer(msg.sender, amount);
    }

    function claimRewards() external nonReentrant{
        _updateRewards(msg.sender);

        uint256 reward = stakes[msg.sender].rewards;
        require(reward > 0, "No Rewards");

        stakes[msg.sender].rewards = 0;
        rewardToken.transfer(msg.sender, reward);
    }
}