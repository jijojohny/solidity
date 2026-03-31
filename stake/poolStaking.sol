//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PoolStaking{
    IERC20 public stakingToken;
    IERC20 public rewardToken;

    uint256 public accRewardPerShare;
    uint256 public lastRewardTime;
    uint256 public rewardPerSecond;
    uint256 public totalStaked;

    struct UserInfo{
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(address => UserInfo ) public users;

    constructor(address _stakingToken, address _rewardToken, uint256 _rewardPerSecond){
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardPerSecond = _rewardPerSecond;
        lastRewardTime = block.timestamp;
    }

    function updatePool() public {
        if (totalStaked == 0){
            lastRewardTime = block.timestamp;
            return;
        }

        uint256 duration = block.timestamp - lastRewardTime;
        uint256 reward = duration * rewardPerSecond;

        accRewardPerShare += (reward * 1e12) / totalStaked;
        lastRewardTime = block.timestamp;
    }

    function deposit(uint256 amount) external {
        UserInfo storage user = users[msg.sender];

        updatePool();

        if(user.amount>0){
            uint256 pending = (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt;
            rewardToken.transfer(msg.sender, pending);
        }
        stakingToken.transferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        totalStaked += amount;

        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;

    }

    function withdraw(uint256 amount) external{
        UserInfo storage user = users[msg.sender];
        require(user.amount>= amount, "Not Enough");

        updatePool();

        uint256 pending = (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt;

        user.amount -= amount;
        totalStaked -= amount;

        stakingToken.transfer(msg.sender, amount);

        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;
    }

}