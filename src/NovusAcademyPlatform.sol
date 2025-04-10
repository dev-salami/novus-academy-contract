// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/security/Pausable.sol";
import "lib/openzeppelin-contracts/contracts/utils/Counters.sol";

interface NovusAcademyCertificate {
    function mintCertificate(address student, uint256 courseId, string memory metadataURI) external returns (uint256);
    function isPlatformSet() external view returns (bool);
}

/**
 * @title NovusAcademyPlatform
 * @dev Main contract for the Novus Academy+ platform with enhanced security
 */
contract NovusAcademyPlatform is Ownable, ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;

    Counters.Counter private _courseIds;

    // Certificate contract
    NovusAcademyCertificate private _certificateContract;

    // Platform fee percentage (in basis points, e.g., 250 = 2.5%)
    uint256 private _platformFeePercentage = 250;

    // Maximum platform fee (10%)
    uint256 private constant _MAX_PLATFORM_FEE = 1000;

    // Track platform fees separately
    uint256 private _platformBalance;

    struct Course {
        uint256 id;
        string title;
        string description;
        string metadataURI; // IPFS URI to course metadata
        address author;
        uint256 price;
        bool isActive;
        uint256 totalEnrollments;
        uint256 creationDate;
    }

    struct Enrollment {
        address student;
        uint256 enrollmentDate;
        bool completed;
        uint256 completionDate;
        bool certificateIssued;
        uint256 certificateId;
    }

    // Maps course ID to Course struct
    mapping(uint256 => Course) private _courses;

    // Maps course ID to array of enrolled students
    mapping(uint256 => address[]) private _courseEnrollments;

    // Maps course ID to mapping of student address to Enrollment struct
    mapping(uint256 => mapping(address => Enrollment)) private _enrollmentDetails;

    // Maps author address to array of created course IDs
    mapping(address => uint256[]) private _authorCourses;

    // Maps student address to array of enrolled course IDs
    mapping(address => uint256[]) private _studentCourses;

    // Maps author address to their earned balance
    mapping(address => uint256) private _authorBalances;

    // Emergency admin address
    address private _emergencyAdmin;

    // Events
    event CourseCreated(uint256 indexed courseId, address indexed author, string title, uint256 price);
    event CourseUpdated(uint256 indexed courseId, string title, uint256 price, bool isActive);
    event CourseEnrollment(uint256 indexed courseId, address indexed student, uint256 price);
    event CourseCompleted(uint256 indexed courseId, address indexed student);
    event CertificateIssued(uint256 indexed courseId, address indexed student, uint256 certificateId);
    event AuthorWithdrawal(address indexed author, uint256 amount);
    event PlatformFeeUpdated(uint256 newFeePercentage);
    event EmergencyAdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event PlatformWithdrawal(address indexed owner, uint256 amount);

    // Modifiers
    modifier onlyEmergencyAdminOrOwner() {
        require(msg.sender == _emergencyAdmin || msg.sender == owner(), "NAP: not emergency admin or owner");
        _;
    }

    modifier courseExists(uint256 courseId) {
        require(_courses[courseId].author != address(0), "NAP: course does not exist");
        _;
    }

    modifier onlyCourseAuthor(uint256 courseId) {
        require(_courses[courseId].author == msg.sender, "NAP: only author can perform this action");
        _;
    }

    constructor(address certificateContract) Ownable() {
        require(certificateContract != address(0), "NAP: certificate contract cannot be zero address");
        _certificateContract = NovusAcademyCertificate(certificateContract);

        _certificateContract.isPlatformSet();
        // Set emergency admin to owner initially
        _emergencyAdmin = msg.sender;
    }

    /**
     * @dev Updates the platform fee percentage
     * @param newFeePercentage New fee percentage in basis points (e.g., 250 = 2.5%)
     */
    function updatePlatformFee(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= _MAX_PLATFORM_FEE, "NAP: fee cannot exceed 10%");
        _platformFeePercentage = newFeePercentage;
        emit PlatformFeeUpdated(newFeePercentage);
    }

    /**
     * @dev Sets or updates the emergency admin
     * @param newEmergencyAdmin Address of the new emergency admin
     */
    function setEmergencyAdmin(address newEmergencyAdmin) external onlyOwner {
        require(newEmergencyAdmin != address(0), "NAP: emergency admin cannot be zero address");
        emit EmergencyAdminChanged(_emergencyAdmin, newEmergencyAdmin);
        _emergencyAdmin = newEmergencyAdmin;
    }

    /**
     * @dev Pause the platform in emergency situations
     */
    function emergencyPause() external onlyEmergencyAdminOrOwner {
        _pause();
    }

    /**
     * @dev Unpause the platform
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Creates a new course
     * @param title Course title
     * @param description Course description
     * @param metadataURI IPFS URI to course metadata
     * @param price Course price in wei
     * @return courseId ID of the created course
     */
    function createCourse(string memory title, string memory description, string memory metadataURI, uint256 price)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(bytes(title).length > 0, "NAP: title cannot be empty");
        require(bytes(description).length > 0, "NAP: description cannot be empty");
        require(bytes(metadataURI).length > 0, "NAP: metadata URI cannot be empty");

        _courseIds.increment();
        uint256 courseId = _courseIds.current();

        _courses[courseId] = Course({
            id: courseId,
            title: title,
            description: description,
            metadataURI: metadataURI,
            author: msg.sender,
            price: price,
            isActive: true,
            totalEnrollments: 0,
            creationDate: block.timestamp
        });

        _authorCourses[msg.sender].push(courseId);

        emit CourseCreated(courseId, msg.sender, title, price);

        return courseId;
    }

    /**
     * @dev Updates an existing course
     * @param courseId ID of the course to update
     * @param title New title (or empty string to keep existing)
     * @param description New description (or empty string to keep existing)
     * @param metadataURI New metadata URI (or empty string to keep existing)
     * @param price New price (or 0 to keep existing)
     * @param isActive New active status
     */
    function updateCourse(
        uint256 courseId,
        string memory title,
        string memory description,
        string memory metadataURI,
        uint256 price,
        bool isActive
    ) external whenNotPaused nonReentrant courseExists(courseId) onlyCourseAuthor(courseId) {
        Course storage course = _courses[courseId];

        if (bytes(title).length > 0) {
            course.title = title;
        }

        if (bytes(description).length > 0) {
            course.description = description;
        }

        if (bytes(metadataURI).length > 0) {
            course.metadataURI = metadataURI;
        }

        if (price > 0) {
            course.price = price;
        }

        course.isActive = isActive;

        emit CourseUpdated(courseId, course.title, course.price, course.isActive);
    }

    /**
     * @dev Enrolls a student in a course
     * @param courseId ID of the course to enroll in
     */
    function enrollInCourse(uint256 courseId) external payable whenNotPaused nonReentrant courseExists(courseId) {
        Course storage course = _courses[courseId];

        require(course.isActive, "NAP: course is not active");
        require(msg.value >= course.price, "NAP: insufficient payment");
        require(_enrollmentDetails[courseId][msg.sender].student == address(0), "NAP: already enrolled");

        // Calculate platform fee
        uint256 platformFee = (course.price * _platformFeePercentage) / 10000;
        uint256 authorPayment = course.price - platformFee;

        // Update balances
        _authorBalances[course.author] += authorPayment;
        _platformBalance += platformFee;

        // Refund excess payment if any
        if (msg.value > course.price) {
            (bool success,) = payable(msg.sender).call{value: msg.value - course.price}("");
            require(success, "NAP: refund failed");
        }

        // Record enrollment
        _enrollmentDetails[courseId][msg.sender] = Enrollment({
            student: msg.sender,
            enrollmentDate: block.timestamp,
            completed: false,
            completionDate: 0,
            certificateIssued: false,
            certificateId: 0
        });

        _courseEnrollments[courseId].push(msg.sender);
        _studentCourses[msg.sender].push(courseId);

        course.totalEnrollments++;

        emit CourseEnrollment(courseId, msg.sender, course.price);
    }

    /**
     * @dev Marks a course as completed for a student (only callable by the course author)
     * @param courseId ID of the completed course
     * @param student Address of the student
     * @param certificateURI IPFS URI to the certificate metadata
     */
    function completeCourse(uint256 courseId, address student, string memory certificateURI)
        external
        whenNotPaused
        nonReentrant
        courseExists(courseId)
        onlyCourseAuthor(courseId)
    {
        require(student != address(0), "NAP: student cannot be zero address");
        require(bytes(certificateURI).length > 0, "NAP: certificate URI cannot be empty");

        Enrollment storage enrollment = _enrollmentDetails[courseId][student];
        require(enrollment.student != address(0), "NAP: student not enrolled");
        require(!enrollment.completed, "NAP: course already completed");

        enrollment.completed = true;
        enrollment.completionDate = block.timestamp;

        emit CourseCompleted(courseId, student);

        try _certificateContract.mintCertificate(student, courseId, certificateURI) returns (uint256 certificateId) {
            enrollment.certificateIssued = true;
            enrollment.certificateId = certificateId;

            emit CertificateIssued(courseId, student, certificateId);
        } catch {
            // Certificate minting failed, but course completion is still recorded
            // This allows retrying certificate issuance later if needed
            enrollment.certificateIssued = false;
        }
    }

    /**
     * @dev Retry certificate issuance if it failed during course completion
     * @param courseId ID of the completed course
     * @param student Address of the student
     * @param certificateURI IPFS URI to the certificate metadata
     */
    function retryCertificateIssuance(uint256 courseId, address student, string memory certificateURI)
        external
        whenNotPaused
        nonReentrant
        courseExists(courseId)
        onlyCourseAuthor(courseId)
    {
        Enrollment storage enrollment = _enrollmentDetails[courseId][student];
        require(enrollment.student != address(0), "NAP: student not enrolled");
        require(enrollment.completed, "NAP: course not completed");
        require(!enrollment.certificateIssued, "NAP: certificate already issued");

        uint256 certificateId = _certificateContract.mintCertificate(student, courseId, certificateURI);

        enrollment.certificateIssued = true;
        enrollment.certificateId = certificateId;

        emit CertificateIssued(courseId, student, certificateId);
    }

    /**
     * @dev Allows an author to withdraw their earned balance
     */
    function authorWithdraw() external nonReentrant {
        uint256 amount = _authorBalances[msg.sender];
        require(amount > 0, "NAP: no balance to withdraw");

        // Set balance to 0 before transfer to prevent reentrancy
        _authorBalances[msg.sender] = 0;

        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "NAP: transfer failed");

        emit AuthorWithdrawal(msg.sender, amount);
    }

    /**
     * @dev Allows the platform owner to withdraw accumulated platform fees
     */
    function platformWithdraw() external onlyOwner nonReentrant {
        uint256 amount = _platformBalance;
        require(amount > 0, "NAP: no platform fees to withdraw");

        // Reset platform balance before transfer
        _platformBalance = 0;

        (bool success,) = payable(owner()).call{value: amount}("");
        require(success, "NAP: transfer failed");

        emit PlatformWithdrawal(owner(), amount);
    }

    /**
     * @dev Gets details of a course
     * @param courseId ID of the course
     * @return Course details
     */
    function getCourse(uint256 courseId) external view courseExists(courseId) returns (Course memory) {
        return _courses[courseId];
    }

    /**
     * @dev Gets the enrollment details for a student in a course
     * @param courseId ID of the course
     * @param student Address of the student
     * @return Enrollment details
     */
    function getEnrollment(uint256 courseId, address student)
        external
        view
        courseExists(courseId)
        returns (Enrollment memory)
    {
        return _enrollmentDetails[courseId][student];
    }

    /**
     * @dev Gets all courses created by an author
     * @param author Address of the author
     * @return Array of course IDs
     */
    function getAuthorCourses(address author) external view returns (uint256[] memory) {
        return _authorCourses[author];
    }

    /**
     * @dev Gets all courses enrolled by a student
     * @param student Address of the student
     * @return Array of course IDs
     */
    function getStudentCourses(address student) external view returns (uint256[] memory) {
        return _studentCourses[student];
    }

    /**
     * @dev Gets all students enrolled in a course
     * @param courseId ID of the course
     * @return Array of student addresses
     */
    function getCourseStudents(uint256 courseId) external view courseExists(courseId) returns (address[] memory) {
        return _courseEnrollments[courseId];
    }

    /**
     * @dev Gets the current balance of an author
     * @param author Address of the author
     * @return Author's current balance
     */
    function getAuthorBalance(address author) external view returns (uint256) {
        return _authorBalances[author];
    }

    /**
     * @dev Gets the current platform fee percentage
     * @return Fee percentage in basis points
     */
    function getPlatformFeePercentage() external view returns (uint256) {
        return _platformFeePercentage;
    }

    /**
     * @dev Gets the current platform balance
     * @return Current platform balance
     */
    function getPlatformBalance() external view returns (uint256) {
        return _platformBalance;
    }

    /**
     * @dev Gets the emergency admin address
     * @return Address of the emergency admin
     */
    function getEmergencyAdmin() external view onlyOwner returns (address) {
        return _emergencyAdmin;
    }

    /**
     * @dev Get the certificate contract address
     * @return Address of the certificate contract
     */
    function getCertificateContract() external view returns (address) {
        return address(_certificateContract);
    }
}
