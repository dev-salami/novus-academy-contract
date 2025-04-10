// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/Counters.sol";
import "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/security/Pausable.sol";

/**
 * @title NovusAcademyCertificate
 * @dev ERC721 token for course completion certificates with enhanced security
 */
contract NovusAcademyCertificate is ERC721URIStorage, Ownable, ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    // Mapping from certificate ID to course ID
    mapping(uint256 => uint256) private _certificateToCourse;

    // Mapping from student address to array of certificate IDs
    mapping(address => uint256[]) private _studentCertificates;

    // Address of the NovusAcademyPlatform contract that can mint certificates
    address private _platformAddress;

    // Flag to track initialization status
    bool private _initialized;

    event CertificateMinted(address indexed student, uint256 courseId, uint256 certificateId);
    event PlatformAddressChanged(address indexed oldPlatform, address indexed newPlatform);

    modifier onlyPlatform() {
        require(msg.sender == _platformAddress, "NAC: caller is not the platform");
        _;
    }

    constructor() ERC721("Novus Academy Certificate", "NAC") Ownable() {
        _pause(); // Start paused until platform address is set
    }

    /**
     * @dev Sets the platform address that is authorized to mint certificates
     * @param platformAddress Address of the NovusAcademyPlatform contract
     */
    function setPlatformAddress(address platformAddress) external onlyOwner {
        require(platformAddress != address(0), "NAC: platform address cannot be zero");

        // For security, emit event with old and new address
        emit PlatformAddressChanged(_platformAddress, platformAddress);

        _platformAddress = platformAddress;

        // Unpause the contract if it was initially paused
        if (paused()) {
            _unpause();
        }
    }

    /**
     * @dev Emergency pause function for critical situations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        require(_platformAddress != address(0), "NAC: platform address not set");
        _unpause();
    }

    /**
     * @dev Mints a new certificate NFT
     * @param student Address of the student who completed the course
     * @param courseId ID of the completed course
     * @param metadataURI IPFS URI to the certificate metadata
     * @return certificateId ID of the minted certificate
     */
    function mintCertificate(address student, uint256 courseId, string memory metadataURI)
        external
        onlyPlatform
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(student != address(0), "NAC: cannot mint to zero address");
        require(bytes(metadataURI).length > 0, "NAC: empty metadata URI");

        _tokenIds.increment();
        uint256 certificateId = _tokenIds.current();

        _mint(student, certificateId);
        _setTokenURI(certificateId, metadataURI);

        _certificateToCourse[certificateId] = courseId;
        _studentCertificates[student].push(certificateId);

        emit CertificateMinted(student, courseId, certificateId);

        return certificateId;
    }

    /**
     * @dev Gets the course ID for a certificate
     * @param certificateId ID of the certificate
     * @return courseId ID of the course
     */
    function getCertificateCourse(uint256 certificateId) external view returns (uint256) {
        require(_exists(certificateId), "NAC: certificate does not exist");
        return _certificateToCourse[certificateId];
    }

    /**
     * @dev Gets all certificates owned by a student
     * @param student Address of the student
     * @return array of certificate IDs
     */
    function getStudentCertificates(address student) external view returns (uint256[] memory) {
        return _studentCertificates[student];
    }

    /**
     * @dev Verifies if a student has completed a specific course
     * @param student Address of the student
     * @param courseId ID of the course
     * @return bool True if the student has completed the course
     */
    function verifyCourseCompletion(address student, uint256 courseId) external view returns (bool) {
        uint256[] memory certificates = _studentCertificates[student];

        for (uint256 i = 0; i < certificates.length; i++) {
            if (_certificateToCourse[certificates[i]] == courseId) {
                return true;
            }
        }

        return false;
    }

    /**
     * @dev Checks if platform address is set
     * @return bool True if platform address is set
     */
    function isPlatformSet() external view returns (bool) {
        return _platformAddress != address(0);
    }

    /**
     * @dev Returns the platform address
     * @return address The platform address
     */
    function getPlatformAddress() external view onlyOwner returns (address) {
        return _platformAddress;
    }
}
