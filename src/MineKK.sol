// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IKK {
    function mint(address to, uint amount) external;
}

contract MineKK {
    address public kkAddress;
    address public weth;
    uint public immutable perReward;
    using SafeERC20 for IERC20;

    struct stakeEntity {
        uint256 stakeAmount;
        uint256 reward;
        uint256 stakeBlock;
    }
    mapping(address => stakeEntity) stakeMap;

    constructor(address _kkAddress, address _weth, uint _perReward) {
        kkAddress = _kkAddress;
        weth = _weth;
        perReward = _perReward;
    }

    function stake(uint wethAmount) public {
        require(wethAmount > 0, "amount must be greater than 0");

        stakeEntity memory entity = stakeMap[msg.sender];
        // 更新收益
        uint earn = pendingEarn(entity);
        // 更新质押信息
        updateEntity(entity, wethAmount, earn, true);

        IERC20(weth).safeTransferFrom(msg.sender, address(this), wethAmount);
    }

    function unstake(uint wethAmount,bool isAll) public {
        require(wethAmount > 0, "amount must be greater than 0");

        stakeEntity memory entity = stakeMap[msg.sender];
        require(entity.stakeAmount >= wethAmount, "amount must be less than or equal to stakeAmount");
        uint unstakeAmount = isAll ? entity.stakeAmount : wethAmount;
        // 更新收益
        uint earn = pendingEarn(entity);
        // 更新质押信息
        updateEntity(entity, unstakeAmount, earn, false);

        IERC20(weth).safeTransfer(msg.sender, wethAmount);
    }

    function claimReward(address user, uint amount) public {
         require(amount > 0, "amount must bigger than zero");
        stakeEntity memory entity = stakeMap[user];
        require(entity.reward >= amount, "not enough reward");
        entity.reward -= amount;
        // 发放收益
        IKK(kkAddress).mint(user, amount);
        stakeMap[user] = entity;
    }

    function pendingEarn(
        stakeEntity memory entity
    ) public view returns (uint reward) {
        if (entity.stakeAmount == 0) return 0;
        uint blockNum = block.number;
        reward = (blockNum - entity.stakeBlock) * 100;
    }

    function updateEntity(
        stakeEntity memory entity,
        uint wethAmount,
        uint earn,
        bool isAdd
    ) public {
        isAdd
            ? entity.stakeAmount += wethAmount
            : entity.stakeAmount -= wethAmount;
        entity.reward += earn;
        entity.stakeBlock = block.number;
        stakeMap[msg.sender] = entity;
    }
}
