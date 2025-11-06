// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AxiomStream.sol";
import "../src/ServiceRegistry.sol";

/**
 * @title DeployAxiomPay
 * @notice Deployment script for AxiomPay protocol contracts
 * @dev Run with: forge script script/DeployAxiomPay.s.sol:DeployAxiomPay --rpc-url <RPC_URL> --broadcast --verify
 */
contract DeployAxiomPay is Script {
    // Default deployment parameters
    uint256 public constant DEFAULT_PROTOCOL_FEE_BPS = 10; // 0.10%
    uint256 public constant DEFAULT_REGISTRATION_FEE = 0.001 ether;

    function run() external {
        // Read deployment configuration from environment
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Optional: custom fee configuration
        uint256 protocolFeeBps = vm.envOr("PROTOCOL_FEE_BPS", DEFAULT_PROTOCOL_FEE_BPS);
        uint256 registrationFee = vm.envOr("REGISTRATION_FEE", DEFAULT_REGISTRATION_FEE);

        console.log("Deploying AxiomPay contracts...");
        console.log("Deployer:");
        console.log(deployerAddress);
        console.log("Protocol Fee (bps):");
        console.log(protocolFeeBps);
        console.log("Registration Fee:");
        console.log(registrationFee);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy AxiomStream
        AxiomStream axiomStream = new AxiomStream(deployerAddress, protocolFeeBps);
        console.log("AxiomStream deployed at:");
        console.log(address(axiomStream));

        // Deploy ServiceRegistry
        ServiceRegistry serviceRegistry = new ServiceRegistry(deployerAddress, registrationFee);
        console.log("ServiceRegistry deployed at:");
        console.log(address(serviceRegistry));

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("AxiomStream:");
        console.log(address(axiomStream));
        console.log("ServiceRegistry:");
        console.log(address(serviceRegistry));
        console.log("Owner:");
        console.log(deployerAddress);
    }
}
