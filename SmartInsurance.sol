// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract SmartInsurance {
    uint256 private policyCounter;
    uint256 private claimCounter;
    address public owner;
    enum PolicyStatus {
        Pending,
        Active,
        PremiumPaid,
        Expired,
        Cancelled,
        Lapsed,
        UnderClaim,
        ClaimApproved, // 7
        ClaimRejected,
        ClaimSettled
    }

    struct Policy {
        uint256 policyId;
        address policyHolder;
        uint256 premiumAmount;
        uint256 coverageAmount;
        uint256 startDate;
        uint256 endDate;
        uint256 policyDuration; // Duration in days
        PolicyStatus status;
    }

    struct Claim {
        uint256 policyId;
        uint256 claimAmount;
        string reason;
        bool isSettled;
    }

    // Constructor to set the contract owner
    constructor() {
        owner = msg.sender;
    }

    mapping(uint256 => Policy) public policies; // Map policy ID to Policy struct
    mapping(uint256 => Claim) public claims;
    mapping(address => uint256[]) public userPolicies;
    mapping(address => uint256[]) public userClaims;
    mapping(address => bool) private authorizedInsurers;

    // Only owner modifier.
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    // Modifier to restrict access to only authorized insurers
    modifier onlyAuthorizedInsurer() {
        require(authorizedInsurers[msg.sender], "Not an authorized insurer");
        _;
    }

    // Events.
    event PolicyIssued(
        uint256 policyId,
        address indexed policyHolder,
        uint256 coverageAmount,
        uint256 premiumAmount
    );
    event InsurerAuthorized(address indexed insurer);
    event InsurerRevoked(address indexed insurer);
    event ClaimSubmitted(
        uint256 claimId,
        uint256 policyId,
        address indexed policyHolder,
        uint256 claimAmount,
        string reason
    );
    event PremiumPaid(
        uint256 policyId,
        address indexed policyHolder,
        uint256 amount
    );
    event ClaimApproved(
        uint256 claimId,
        uint256 policyId,
        uint256 claimAmount,
        address policyHolder
    );
    event ClaimPaid(
        uint256 claimId,
        uint256 policyId,
        uint256 payoutAmount,
        address policyHolder
    );

    // Function to authorize an insurer (owner-only)
    function authorizeInsurer(address _insurer) external onlyOwner {
        require(_insurer != address(0), "Invalid insurer address");
        authorizedInsurers[_insurer] = true;
        emit InsurerAuthorized(_insurer);
    }

    // Function to revoke an insurer's authorization (owner-only)
    function revokeInsurer(address _insurer) external onlyOwner {
        require(_insurer != address(0), "Invalid insurer address");
        authorizedInsurers[_insurer] = false;
        emit InsurerRevoked(_insurer);
    }

    // Function to check if an address is authorized
    function isAuthorizedInsurer(address _insurer)
        external
        view
        returns (bool)
    {
        return authorizedInsurers[_insurer];
    }

    // Function to issue policy.
    function issuePolicy(
        address _policyHolder,
        uint256 _premiumAmount,
        uint256 _coverageAmount,
        uint256 _policyDuration // Duration in days
    ) external onlyAuthorizedInsurer returns (uint256) {
        // address(0) => It represents the null address in Ethereum, which is not owned by anyone.
        require(_policyHolder != address(0), "Invalid policy holder address");
        require(_premiumAmount > 0, "Premium amount must be greater than 0");
        require(_coverageAmount > 0, "Coverage amount must be greater than 0");
        require(_policyDuration > 0, "Policy duration must be greater than 0");

        policyCounter++;

        uint256 startDate = block.timestamp;
        uint256 endDate = startDate + (_policyDuration + 1 days);

        policies[policyCounter] = Policy({
            policyId: policyCounter,
            policyHolder: _policyHolder,
            premiumAmount: _premiumAmount,
            coverageAmount: _coverageAmount,
            startDate: startDate,
            endDate: endDate,
            policyDuration: _policyDuration,
            status: PolicyStatus.Active
        });

        userPolicies[_policyHolder].push(policyCounter);

        emit PolicyIssued(
            policyCounter,
            _policyHolder,
            _coverageAmount,
            _premiumAmount
        );

        return policyCounter;
    }

    // Function to pay premium.
    function payPremium(uint256 policyId) external payable {
        Policy storage policy = policies[policyId];

        // Ensure the policy exists and is active
        require(policy.policyHolder == msg.sender, "Not the policy holder");
        require(
            policy.status == PolicyStatus.Active ||
                policy.status == PolicyStatus.PremiumPaid,
            "Policy not active"
        );

        // Ensure the correct premium amount is sent
        require(msg.value == policy.premiumAmount, "Incorrect premium amount");

        // Mark the policy as premium paid
        policy.status = PolicyStatus.PremiumPaid;

        emit PremiumPaid(policyId, msg.sender, msg.value);
    }

    // Function to submit a claim
    function submitClaim(
        uint256 _policyId,
        uint256 _claimAmount,
        string calldata _reason
    ) external {
        Policy storage policy = policies[_policyId];

        // Ensure the policy exists
        require(policy.policyId != 0, "Policy does not exist");

        // Ensure the policy exists
        require(policy.policyId != 0, "Policy does not exist");

        // Ensure the caller is the policyholder
        require(policy.policyHolder == msg.sender, "Not the policyholder");

        // Ensure the policy is active
        require(
            policy.status == PolicyStatus.Active ||
                policy.status == PolicyStatus.PremiumPaid,
            "Policy not active"
        );

        // Ensure the policy has not expired
        require(block.timestamp <= policy.endDate, "Policy has expired");

        // Ensure a valid claim amount
        require(
            _claimAmount > 0 && _claimAmount <= policy.coverageAmount,
            "Invalid claim amount"
        );

        // Update the policy status.
        policy.status = PolicyStatus.UnderClaim;

        // Increment the claim counter
        claimCounter++;

        // Record the claim details
        claims[claimCounter] = Claim({
            policyId: _policyId,
            claimAmount: _claimAmount,
            reason: _reason,
            isSettled: false
        });

        // Add the claim to the user's claims list
        userClaims[msg.sender].push(claimCounter);

        // Emit the claim submission event
        emit ClaimSubmitted(
            claimCounter,
            _policyId,
            msg.sender,
            _claimAmount,
            _reason
        );
    }

    // Function to approve a claim
    function approveClaim(uint256 _claimId) external onlyAuthorizedInsurer {
        Claim storage claim = claims[_claimId];

        // Ensure the claim exists
        require(claim.policyId != 0, "Claim does not exist");

        // Fetch the associated policy
        Policy storage policy = policies[claim.policyId];

        // Ensure the policy exists
        require(policy.policyId != 0, "Policy does not exist");

        // Ensure the claim is associated with an active policy
        require(
            policy.status == PolicyStatus.UnderClaim,
            "Policy not under claim"
        );

        // Ensure the claim is not already settled
        require(!claim.isSettled, "Claim already settled");

        // Approve the claim
        policy.status = PolicyStatus.ClaimApproved;

        emit ClaimApproved(
            _claimId,
            claim.policyId,
            claim.claimAmount,
            policy.policyHolder
        );
    }

    // Function to pay claim.
    function payClaim(uint256 _claimId) external onlyAuthorizedInsurer {
        Claim storage claim = claims[_claimId];

        // Ensure the claim exists
        require(claim.policyId != 0, "Claim does not exist");

        // Fetch the associated policy
        Policy storage policy = policies[claim.policyId];

        // Ensure the policy exists
        require(policy.policyId != 0, "Policy does not exist");

        // Ensure the claim is approved
        require(
            policy.status == PolicyStatus.ClaimApproved,
            "Claim not approved"
        );

        // Ensure the claim is not already settled
        require(!claim.isSettled, "Claim already settled");

        // Mark the claim as settled
        claim.isSettled = true;

        policy.status = PolicyStatus.ClaimSettled;

        // Transfer the claim amount to the policyholder
        // payable(policy.policyHolder).transfer(claim.claimAmount);

        //Emit claimPaid Event.
        emit ClaimPaid(
            _claimId,
            claim.policyId,
            claim.claimAmount,
            policy.policyHolder
        );
    }

    // Function to get user policies
    function getUserPolicies(address _user)
        external
        view
        returns (uint256[] memory)
    {
        return userPolicies[_user];
    }

    // Function to get user claims
    function getUserClaims(address _user)
        external
        view
        returns (uint256[] memory)
    {
        return userClaims[_user];
    }

    // Fallback function to accept Ether deposits into the contract
    receive() external payable {}

    // Function to get the balance of the provided address
    function getBalance(address _user) public view returns (uint256) {
        return _user.balance;
    }
}


