// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract KKToken is ERC20, Ownable{

    constructor(address mineAddr) ERC20("KaKa", "KK") Ownable(mineAddr){
    }

    function mint(address to, uint amount) public onlyOwner{
        _mint(to,amount);
    }

    function burn(address account, uint amount) public onlyOwner {
        _burn(account,amount);
    }
    
}
