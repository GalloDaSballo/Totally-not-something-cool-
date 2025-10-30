// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Owned } from "solmate/auth/Owned.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

contract BadStakeFixed is Owned, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    uint256 uselessvariable;

    uint256 constant WAD = 1e18;

    ERC20 public depositToken;
    ERC20 public rewardToken;

    // 1e18 / 86400 rounded down. 
    uint256 public rewardPerDepositTokenPerSecond = 11_574_074_074_074;
    uint256 public accumulatedRewardsPerDepositToken = 0;
    uint256 public totalDeposits = 0;
    uint40 public lastUpdateTime = uint40(block.timestamp);

    struct DepositInfo {
        uint256 debt;
        uint256 balance;
    }

    mapping(address staker => DepositInfo) public deposits;

    event Deposit(address indexed staker, uint256 amount);
    event Withdraw(address indexed staker, uint256 amount);
    event EmergencyWithdraw(address indexed staker, uint256 amount);
    event SetRewardRate(uint256 time, uint256 rate);
    event ClaimForCTF(address indexed player, uint256 amount);

    constructor (ERC20 _depositToken, ERC20 _rewardToken) Owned(msg.sender) {
        depositToken = _depositToken;
        rewardToken = _rewardToken;
    }

    function claimForCTF() external {
        depositToken.safeTransfer(msg.sender, 100e18);
        emit ClaimForCTF(msg.sender, 100e18);
    }

    function setRewardRate(uint256 _rewardPerDepositTokenPerSecond) external onlyOwner {
        _accrueRewards();
        rewardPerDepositTokenPerSecond = _rewardPerDepositTokenPerSecond;
        emit SetRewardRate(block.timestamp, _rewardPerDepositTokenPerSecond);
    }

    function deposit(uint256 amount) external nonReentrant {
        _accrueRewards();
        _transferRewardsAndUpdateAccount(msg.sender, amount, true);
        depositToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        _accrueRewards();
        _transferRewardsAndUpdateAccount(msg.sender, amount, false);
        depositToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function emergencyWithdraw() external nonReentrant {
        _accrueRewards();
        uint256 amount = deposits[msg.sender].balance;
        depositToken.safeTransfer(msg.sender, amount);
        deposits[msg.sender].balance = 0;
        deposits[msg.sender].debt = 0;
        totalDeposits -= amount;

        emit EmergencyWithdraw(msg.sender, amount);
    }

    function _accrueRewards() internal {
        uint40 timeElapsed = uint40(block.timestamp) - lastUpdateTime;
        if (totalDeposits > 0) {
            accumulatedRewardsPerDepositToken += (timeElapsed * rewardPerDepositTokenPerSecond * WAD) / totalDeposits;
        }

        lastUpdateTime = uint40(block.timestamp);
    }

    function _transferRewardsAndUpdateAccount(address depositor, uint256 amount, bool isDeposit) internal {
        DepositInfo storage d = deposits[depositor];

        uint256 currentAccruedValue = d.balance * accumulatedRewardsPerDepositToken / WAD;
        uint256 rewardsOwed = currentAccruedValue > d.debt ? currentAccruedValue - d.debt : 0;

        uint256 availableRewards = rewardToken.balanceOf(address(this));
        uint256 rewardsToSend = rewardsOwed > availableRewards ? availableRewards : rewardsOwed;

        if (rewardsToSend > 0) {
            rewardToken.safeTransfer(depositor, rewardsToSend);
        }

        if (isDeposit) {
            deposits[depositor].balance += amount;
            totalDeposits += amount;
        } else {
            deposits[depositor].balance -= amount;
            totalDeposits -= amount;
        }

        deposits[depositor].debt = rewardsToSend;
    }
}
