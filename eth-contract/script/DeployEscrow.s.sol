// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EthereumEscrow} from "../src/core/EthereumEscrow.sol";
import {DutchAuction} from "../src/core/DutchAuction.sol";
import {ResolverNetwork} from "../src/core/ResolverNetwork.sol";
import {LimitOrderProtocol} from "../src/core/LimitOrderProtocol.sol";
import {CrossChainOrder} from "../src/core/CrossChainOrder.sol";

/**
 * @title DeployEscrow
 * @dev Deployment script for all Unite-SUI contracts
 */
contract DeployEscrow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Sepolia WETH address
        address wethAddress = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        address deployer = vm.addr(deployerPrivateKey);
        
        // 1. Deploy EthereumEscrow contract with WETH support
        EthereumEscrow escrow = new EthereumEscrow(wethAddress);
        console.log("EthereumEscrow deployed at:", address(escrow));
        
        // 2. Deploy DutchAuction (needs LimitOrderProtocol address, but we'll set it later)
        DutchAuction dutchAuction = new DutchAuction(address(0)); // Temporary address
        console.log("DutchAuction deployed at:", address(dutchAuction));
        
        // 3. Deploy ResolverNetwork (needs LimitOrderProtocol address, but we'll set it later)
        ResolverNetwork resolverNetwork = new ResolverNetwork(address(0), wethAddress, deployer);
        console.log("ResolverNetwork deployed at:", address(resolverNetwork));
        
        // 4. Deploy LimitOrderProtocol (needs all other contracts)
        LimitOrderProtocol limitOrderProtocol = new LimitOrderProtocol(
            wethAddress,
            address(dutchAuction),
            address(resolverNetwork),
            address(escrow)
        );
        console.log("LimitOrderProtocol deployed at:", address(limitOrderProtocol));
        
        // 5. Deploy CrossChainOrder (needs all other contracts)
        CrossChainOrder crossChainOrder = new CrossChainOrder(
            address(limitOrderProtocol),
            address(escrow),
            address(dutchAuction),
            address(resolverNetwork),
            wethAddress
        );
        console.log("CrossChainOrder deployed at:", address(crossChainOrder));
        
        vm.stopBroadcast();
        
        // Log deployment information
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Sepolia Testnet");
        console.log("WETH Address:", wethAddress);
        console.log("Deployer address:", deployer);
        console.log("Block number:", block.number);
        console.log("Block timestamp:", block.timestamp);
        console.log("\nContract Addresses:");
        console.log("ETH_CROSSCHAIN_ORDER_ADDRESS=", address(crossChainOrder));
        console.log("ETH_LIMIT_ORDER_PROTOCOL_ADDRESS=", address(limitOrderProtocol));
        console.log("ETH_DUTCH_AUCTION_ADDRESS=", address(dutchAuction));
        console.log("ETH_RESOLVER_NETWORK_ADDRESS=", address(resolverNetwork));
        console.log("ETH_ESCROW_ADDRESS=", address(escrow));
        
        // Verify basic contract functionality
        console.log("\n=== Contract Verification ===");
        console.log("EthereumEscrow balance:", escrow.getContractBalance());
        console.log("All contracts deployed successfully!");
        
        // Note: DutchAuction and ResolverNetwork need to be updated with LimitOrderProtocol address
        // This would require additional transactions to update the addresses
        console.log("\n=== Important Note ===");
        console.log("DutchAuction and ResolverNetwork were deployed with temporary addresses.");
        console.log("They need to be updated with the actual LimitOrderProtocol address.");
        console.log("This requires additional contract upgrades or redeployment.");
    }
}