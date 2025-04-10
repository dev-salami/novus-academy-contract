// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import "../src/NovusAcademyPlatform.sol";

// Mock Certificate Contract for testing
contract MockCertificate {
    bool public isPlatformSet = true;

    function mintCertificate(address, uint256, string memory) external returns (uint256) {
        return 1;
    }
}

contract PlatformFeeTest is Test {
    NovusAcademyPlatform public platform;
    MockCertificate public certificate;

    address public owner = address(1);
    address public author = address(2);
    address public student = address(3);

    uint256 public coursePrice = 1 ether;

    event PlatformWithdrawal(address indexed owner, uint256 amount);
    event AuthorWithdrawal(address indexed author, uint256 amount);

    function setUp() public {
        // Deploy mock certificate
        certificate = new MockCertificate();

        // Deploy platform with mock certificate
        vm.prank(owner);
        platform = new NovusAcademyPlatform(address(certificate));

        // Fund accounts
        vm.deal(student, 10 ether);
        vm.deal(author, 1 ether);

        // Create course
        vm.prank(author);
        platform.createCourse("Test Course", "Test Description", "ipfs://testURI", coursePrice);
    }

    function testFeeTracking() public {
        // Initial balances should be zero
        assertEq(platform.getPlatformBalance(), 0);
        assertEq(platform.getAuthorBalance(author), 0);

        // Enroll student
        vm.prank(student);
        platform.enrollInCourse{value: coursePrice}(1);

        // Calculate expected platform fee (2.5%)
        uint256 platformFee = (coursePrice * 250) / 10000;
        uint256 authorPayment = coursePrice - platformFee;

        // Verify balances are tracked correctly
        assertEq(platform.getPlatformBalance(), platformFee);
        assertEq(platform.getAuthorBalance(author), authorPayment);
        assertEq(address(platform).balance, platformFee + authorPayment);
    }

    function testAuthorWithdrawalDoesNotAffectPlatformFees() public {
        // Enroll student
        vm.prank(student);
        platform.enrollInCourse{value: coursePrice}(1);

        // Calculate expected platform fee (2.5%)
        uint256 platformFee = (coursePrice * 250) / 10000;
        uint256 authorPayment = coursePrice - platformFee;

        // Record initial balances
        uint256 initialAuthorBalance = author.balance;
        uint256 initialContractBalance = address(platform).balance;

        // Author withdraws their balance
        vm.prank(author);
        platform.authorWithdraw();

        // Verify author received correct payment
        assertEq(author.balance, initialAuthorBalance + authorPayment);

        // Verify platform balance unchanged
        assertEq(platform.getPlatformBalance(), platformFee);

        // Verify contract balance reduced by only author payment
        assertEq(address(platform).balance, initialContractBalance - authorPayment);
        assertEq(address(platform).balance, platformFee);
    }

    function testPlatformWithdrawalDoesNotAffectAuthorBalance() public {
        // Enroll student
        vm.prank(student);
        platform.enrollInCourse{value: coursePrice}(1);

        // Calculate expected platform fee (2.5%)
        uint256 platformFee = (coursePrice * 250) / 10000;
        uint256 authorPayment = coursePrice - platformFee;

        // Record initial balances
        uint256 initialOwnerBalance = owner.balance;
        uint256 initialContractBalance = address(platform).balance;

        // Platform owner withdraws platform fees
        vm.prank(owner);
        platform.platformWithdraw();

        // Verify owner received correct platform fees
        assertEq(owner.balance, initialOwnerBalance + platformFee);

        // Verify author balance unchanged
        assertEq(platform.getAuthorBalance(author), authorPayment);

        // Verify platform balance reset
        assertEq(platform.getPlatformBalance(), 0);

        // Verify contract balance reduced by only platform fee
        assertEq(address(platform).balance, initialContractBalance - platformFee);
        assertEq(address(platform).balance, authorPayment);
    }

    function testMultipleEnrollmentsAccumulateFees() public {
        // Enroll first student
        vm.prank(student);
        platform.enrollInCourse{value: coursePrice}(1);

        // Create second student
        address student2 = address(4);
        vm.deal(student2, 10 ether);

        // Enroll second student
        vm.prank(student2);
        platform.enrollInCourse{value: coursePrice}(1);

        // Calculate expected platform fees for two enrollments
        uint256 platformFeePerEnrollment = (coursePrice * 250) / 10000;
        uint256 totalPlatformFee = platformFeePerEnrollment * 2;
        uint256 totalAuthorPayment = (coursePrice - platformFeePerEnrollment) * 2;

        // Verify balances
        assertEq(platform.getPlatformBalance(), totalPlatformFee);
        assertEq(platform.getAuthorBalance(author), totalAuthorPayment);
        assertEq(address(platform).balance, totalPlatformFee + totalAuthorPayment);
    }

    function testWithdrawSequence() public {
        // Enroll student
        vm.prank(student);
        platform.enrollInCourse{value: coursePrice}(1);

        // Calculate expected platform fee (2.5%)
        uint256 platformFee = (coursePrice * 250) / 10000;
        // uint256 authorPayment = coursePrice - platformFee;

        // Author withdraws first
        vm.prank(author);
        platform.authorWithdraw();

        // Platform withdraws second
        vm.expectEmit(true, false, false, true);
        emit PlatformWithdrawal(owner, platformFee);

        vm.prank(owner);
        platform.platformWithdraw();

        // Contract should now be empty
        assertEq(address(platform).balance, 0);
        assertEq(platform.getPlatformBalance(), 0);
        assertEq(platform.getAuthorBalance(author), 0);
    }

    function testRevertsForInsufficientBalances() public {
        // Try to withdraw with no enrollments
        vm.prank(author);
        vm.expectRevert("NAP: no balance to withdraw");
        platform.authorWithdraw();

        vm.prank(owner);
        vm.expectRevert("NAP: no platform fees to withdraw");
        platform.platformWithdraw();

        // Enroll student
        vm.prank(student);
        platform.enrollInCourse{value: coursePrice}(1);

        // Withdraw both balances
        vm.prank(author);
        platform.authorWithdraw();

        vm.prank(owner);
        platform.platformWithdraw();

        // Try to withdraw again after balances are zero
        vm.prank(author);
        vm.expectRevert("NAP: no balance to withdraw");
        platform.authorWithdraw();

        vm.prank(owner);
        vm.expectRevert("NAP: no platform fees to withdraw");
        platform.platformWithdraw();
    }

    function testFeePercentageUpdate() public {
        // Update platform fee to 5%
        vm.prank(owner);
        platform.updatePlatformFee(500);

        // Enroll student with new fee
        vm.prank(student);
        platform.enrollInCourse{value: coursePrice}(1);

        // Calculate expected platform fee with new percentage
        uint256 platformFee = (coursePrice * 500) / 10000; // 5%
        uint256 authorPayment = coursePrice - platformFee;

        // Verify balances reflect new fee percentage
        assertEq(platform.getPlatformBalance(), platformFee);
        assertEq(platform.getAuthorBalance(author), authorPayment);
    }
}
