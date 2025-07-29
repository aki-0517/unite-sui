// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EthereumEscrow} from "../src/core/EthereumEscrow.sol";

/**
 * @title DeployEscrow
 * @dev Deployment script for EthereumEscrow contract
 */
contract DeployEscrow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Sepolia WETH address
        address wethAddress = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        
        // Deploy EthereumEscrow contract with WETH support
        EthereumEscrow escrow = new EthereumEscrow(wethAddress);
        
        console.log("EthereumEscrow deployed at:", address(escrow));
        console.log("WETH address:", wethAddress);
        console.log("Deployer address:", vm.addr(deployerPrivateKey));
        console.log("Block number:", block.number);
        console.log("Block timestamp:", block.timestamp);
        
        vm.stopBroadcast();
        
        // Log deployment information
        console.log("\n=== Deployment Summary ===");
        console.log("Contract: EthereumEscrow (WETH-enabled)");
        console.log("Address:", address(escrow));
        console.log("WETH Address:", wethAddress);
        console.log("Network: Sepolia Testnet");
        console.log("Gas used: Check transaction receipt");
        
        // Verify basic contract functionality
        console.log("\n=== Contract Verification ===");
        console.log("Contract balance:", escrow.getContractBalance());
        console.log("Deployment successful!");
    }
}