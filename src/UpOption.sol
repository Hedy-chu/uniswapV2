// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * 模拟期权合约
 */
contract UpOption is Ownable, ERC20 {
    using SafeERC20 for IERC20;
    address public buyToken;
    uint public optionPrice;
    uint public strikePrice; // 行权价格
    uint public expiryDate;
    uint public issueMin;

    constructor(
        address _buyToken,
        uint _optionPrice,
        uint _expiryDate
    ) ERC20("UpOption", "UP") Ownable(msg.sender) {
        buyToken = _buyToken;
        optionPrice = _optionPrice;
        expiryDate = _expiryDate;
    }

    /**
     * 发行期权
     */
    function issueOptions() public payable onlyOwner returns (uint amount) {
        require(block.timestamp < expiryDate, "Option expired");
        require(msg.value >= issueMin, "Incorrect option amount");
        amount = msg.value;
        _mint(msg.sender, amount);
    }

    /**
     * 购买期权
     * @param optionAmount 期权的个数
     * @param kkAmount 支付的KK数量
     */
    function buyOption(uint optionAmount, uint kkAmount) public {
        require(
            optionAmount <= balanceOf(msg.sender),
            "Insufficient option amount"
        );
        require(block.timestamp < expiryDate, "Option expired");
        require(
            kkAmount >= optionAmount * optionPrice,
            "Incorrect option price"
        );
        IERC20(buyToken).safeTransferFrom(msg.sender, address(this), kkAmount);
        IERC20(address(this)).safeTransferFrom(
            owner(),
            msg.sender,
            optionAmount
        );
    }

    /**
     * 行使期权
     * @param amount 期权行使价格 optionAmount 凭证的数量
     */

    function exerciseOption(uint amount, uint optionAmount) public {
        require(block.timestamp >= expiryDate, "Option not expired");
        require(amount == strikePrice, "Incorrect option price");
        require(
            optionAmount <= balanceOf(msg.sender),
            "Insufficient option amount"
        );
        require(
            IERC20(buyToken).balanceOf(address(this)) >= optionAmount * amount,
            "Insufficient buy token balance"
        );
        IERC20(buyToken).safeTransferFrom(
            msg.sender,
            owner(),
            optionAmount * amount
        );
        _burn(msg.sender, optionAmount);

        (bool success,) = msg.sender.call{value: optionAmount}("");
        require(success, "Transfer failed");
    }

    /**
     * 项目方销毁期权凭证
     */
    function burnOptions() onlyOwner public{
        _burn(msg.sender, balanceOf(msg.sender));
        (bool success,) = owner().call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    /**
     * 接收ETH
     */
    receive() external payable {}
}
