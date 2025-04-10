// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NovusAcademyCertificate} from "../src/NovusAcademyCertificate.sol";
import {NovusAcademyPlatform} from "../src/NovusAcademyPlatform.sol";
import "forge-std/console2.sol";

/**
 * @title DeployNovusAcademy
 * @dev Script to deploy the Novus Academy platform contracts
 */
contract NovusAcademyDeployScript is Script {
    // Deployment addresses
    NovusAcademyCertificate public certificate;
    NovusAcademyPlatform public platform;

    function run() external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Log deployment info
        console2.log("Deploying Novus Academy contracts with address:", deployer);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Certificate contract
        certificate = new NovusAcademyCertificate();
        console2.log("NovusAcademyCertificate deployed at:", address(certificate));

        // Deploy Platform contract with Certificate address
        platform = new NovusAcademyPlatform(address(certificate));
        console2.log("NovusAcademyPlatform deployed at:", address(platform));

        // Set Platform address in Certificate contract
        certificate.setPlatformAddress(address(platform));
        console2.log("Platform address set in Certificate contract");

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment completed
        console2.log("Deployment completed successfully");
        console2.log("Certificate contract:", address(certificate));
        console2.log("Platform contract:", address(platform));
    }
}
