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
    uint public constant PERWARD = 10; // 每个区块收益
    using SafeERC20 for IERC20;
    uint public totalStake; // 总抵押量
    uint public currentStakeInterest; // 当前利率 初始值 = 0

    struct stakeEntity {
        uint256 stakeAmount;
        uint256 reward;
        uint256 stakeBlock;
        uint stakeInterest; // 上一次存款/赎回时的利率
    }
    mapping(address => stakeEntity) stakeMap;

    constructor(address _kkAddress, address _weth) {
        kkAddress = _kkAddress;
        weth = _weth;
    }

    function stake(uint wethAmount) public {
        require(wethAmount > 0, "amount must be greater than 0");
    
        stakeEntity memory entity = stakeMap[msg.sender];
        // 更新收益
        uint earn = pendingEarn(entity);
        // 更新总质押
        totalStake += wethAmount;
        changeInterest();
        // 更新质押信息
        updateEntity(entity, wethAmount, earn, true);

        IERC20(weth).safeTransferFrom(msg.sender, address(this), wethAmount);
    }

    function unStake(uint wethAmount, bool isAll) public {
        require(wethAmount > 0, "amount must be greater than 0");

        stakeEntity memory entity = stakeMap[msg.sender];
        require(
            entity.stakeAmount >= wethAmount,
            "amount must be less than or equal to stakeAmount"
        );
        uint unStakeAmount = isAll ? entity.stakeAmount : wethAmount;
        // 更新收益
        uint earn = pendingEarn(entity);
        // 更新总质押
        totalStake += wethAmount;
        // 更新总份数额
        changeInterest();
        // 更新质押信息
        updateEntity(entity, unStakeAmount, earn, false);

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
        reward =
            (blockNum - entity.stakeBlock) *
            entity.stakeAmount *
            (currentStakeInterest - entity.stakeInterest);
    }

    /**
     * 更新累计利率
     */
    function changeInterest() internal {
        // percharge = 当前收取的fee/ 总存款
        uint rate = PERWARD / totalStake;
        // 计算当前的累积利率
        currentStakeInterest = currentStakeInterest + rate;
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
        entity.stakeInterest = currentStakeInterest;
        stakeMap[msg.sender] = entity;
    }
}
