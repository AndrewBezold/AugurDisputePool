pragma solidity ^0.4.24;

contract Token {
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool);
    function transfer(address _to, uint256 _value) public returns (bool);
    function allowance(address _owner, address _spender) public view returns (uint256 remaining);
    function balanceOf(address _owner) public view returns (uint256);
}

library SafeMath {

    /**
    * @dev Multiplies two numbers, reverts on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "Multiplication invalid");

        return c;
    }

    /**
    * @dev Integer division of two numbers truncating the quotient, reverts on division by zero.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "Denominator less than or equal to zero."); // Solidity only automatically asserts when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
    * @dev Subtracts two numbers, reverts on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "Result would be negative.");
        uint256 c = a - b;

        return c;
    }

    /**
    * @dev Adds two numbers, reverts on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "Negative input.");

        return c;
    }

    /**
    * @dev Divides two numbers and returns the remainder (unsigned integer modulo),
    * reverts when dividing by zero.
    */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "Division by zero.");
        return a % b;
    }
}

contract Market {
    function derivePayoutDistributionHash(uint256[] _payoutNumerators, bool _invalid) public view returns (bytes32);
    function getNumberOfOutcomes() public view returns (uint256);
    function getReputationToken() public view returns (Token);
    function getNumTicks() public view returns (uint256);
    function getNumParticipants() public view returns (uint256);
    function getReportingParticipant(uint256 _index) public view returns (IReportingParticipant);
    function contribute(uint256[] _payoutNumerators, bool _invalid, uint256 _amount) public returns (bool);
    function getCrowdsourcer(bytes32 _payoutDistributionHash) public view returns (DisputeCrowdsourcer);
    function getStakeInOutcome(bytes32 _payoutDistributionHash) public view returns (uint256);
    function getParticipantStake() public view returns (uint256);
}

contract IReportingParticipant {
    function getSize() public view returns (uint256);
    function totalSupply() public view returns (uint256);
}

contract DisputeCrowdsourcer is IReportingParticipant, Token {}

contract AugurDisputePool {
    using SafeMath for uint256;

    bool public needsClaimed;
    bool public txRun;
    address public txSender;
    mapping(address => uint256) public deposited;
    mapping(address => uint256) public fees;
    uint256 total;

    address marketAddress;
    uint256[] payoutNumerators;
    bool invalid;
    address repAddress;
    bytes32 payoutDistributionHash;
    uint256 roundNumber;
    uint256 constant FEES = 5;
    address disputeTokenAddress;
    uint256 maxDeposits;

    address public owner;

    constructor(
        address _owner,
        address _marketAddress,
        uint256[] _payoutNumerators,
        bool _invalid,
        address _repAddress,
        uint256 _roundNumber,
        uint256 _maxDeposits
    ) public {
        Market market = Market(_marketAddress);
        require(_repAddress == address(market.getReputationToken()), "Incorrect rep address.");
        require(_payoutNumerators.length == market.getNumberOfOutcomes(), "Incorrect payout numerators.");
        owner = _owner;
        marketAddress = _marketAddress;
        payoutNumerators = _payoutNumerators;
        invalid = _invalid;
        repAddress = _repAddress;
        payoutDistributionHash = derivePayoutDistributionHash(payoutNumerators, invalid);
        roundNumber = _roundNumber;
        maxDeposits = _maxDeposits;
    }

    function depositRep(uint256 _quantity) public {
        require(total < maxDeposits, "Max deposits already reached.");
        Token rep = Token(repAddress);

        require(rep.allowance(msg.sender, this) >= _quantity, "Max rep allowance too low.");
        require(needsClaimed == false, "Dispute already submitted and needs claimed.");
        require(txRun == false, "Dispute already submitted and transaction run.");

        if (maxDeposits.sub(total) < _quantity) {
            uint256 newQuantity = maxDeposits.sub(total);
        } else {
            newQuantity = _quantity;
        }

        rep.transferFrom(msg.sender, this, newQuantity);

        deposited[msg.sender] = deposited[msg.sender].add(newQuantity);
        total = total.add(newQuantity);
    }

    function withdrawRep(uint256 _quantity) public {
        Token rep = Token(repAddress);

        require(needsClaimed == false, "Dispute already submitted and needs claimed.");
        require(deposited[msg.sender] <= _quantity, "Attempt to withdraw more than depostied.");

        deposited[msg.sender] = deposited[msg.sender].sub(_quantity);
        total = total.sub(_quantity);

        rep.transfer(msg.sender, _quantity);
    }

    function derivePayoutDistributionHash(uint256[] _payoutNumerators, bool _invalid) internal view returns (bytes32) {
        Market market = Market(marketAddress);
        if (_invalid == true) {
            for(uint256 i = 0; i < _payoutNumerators.length; i++) {
                _payoutNumerators[i] = market.getNumTicks().div(market.getNumberOfOutcomes());
            }
        }
        bytes32 _payoutDistributionHash = market.derivePayoutDistributionHash(_payoutNumerators, _invalid);
        return _payoutDistributionHash;
    }

    function sendDispute() public {
        require(txRun == false, "Dispute already submitted and transaction run.");
        require(needsClaimed == false, "Dispute already submitted and needs claimed.");

        Market market = Market(marketAddress);

        require(roundNumber == market.getNumParticipants(), "Round number not equal to number of participants.");
        require(repAddress == address(market.getReputationToken()), "Incorrect rep address.");

        DisputeCrowdsourcer crowdsourcer = market.getCrowdsourcer(payoutDistributionHash); //does this fail if getCrowdsourcer returns 0?

        //the amount of REP to send equals the max of this dispute round minus what's already in the dispute, minus 0.1 REP so as not to close out the round, saving a bit of gas
        if (address(crowdsourcer) == 0x0) {
            uint256 quantity = market.getParticipantStake().mul(2).sub(market.getStakeInOutcome(payoutDistributionHash).mul(3)).sub(uint256(10**17));
        } else {
            quantity = crowdsourcer.getSize().sub(crowdsourcer.totalSupply()).sub(uint256(10**17)); //wrong
        }

        require(quantity > 0, "Quantity less than or equal to zero");

        //if what we have in the contract is less than what we want to send, send what we've got
        if (total < quantity) {
            quantity = total;
        }

        needsClaimed = true;
        txRun = true;

        market.contribute(payoutNumerators, invalid, quantity);
        txSender = msg.sender;
        disputeTokenAddress = address(market.getCrowdsourcer(payoutDistributionHash));
    }

    function claim() public {
        require(needsClaimed == true, "Dispute not yet sent.  No claims available.");
        require(txRun == true, "Dispute not yet sent.  Transaction not run.");

        Token disputeToken = Token(disputeTokenAddress);
        uint256 disputeTokenBalance = disputeToken.balanceOf(this);

        uint256 notFees = disputeTokenBalance.mul(uint256(100).sub(FEES)).div(100);
        uint256 ownerFees = disputeTokenBalance.sub(notFees).mul(5).div(100);
        uint256 senderFees = disputeTokenBalance.sub(notFees).sub(ownerFees);
        fees[txSender] = fees[txSender].add(senderFees);
        fees[owner] = fees[owner].add(ownerFees);

        needsClaimed = false;
    }

    function withdrawDisputeFees() public {
        require(disputeTokenAddress != 0x0, "Missing dispute token address.");
        uint256 f = fees[msg.sender];
        fees[msg.sender] = 0;
        Token d = Token(disputeTokenAddress);
        d.transfer(msg.sender, f);
    }

    function withdrawWinnings() public {
        require(txRun == true, "Dispute not yet sent.  Transaction not run.");
        require(needsClaimed == false, "Claim before withdrawing winnings.");

        Token disputeToken = Token(disputeTokenAddress);

        uint256 quantity = disputeToken.balanceOf(this).sub(fees[txSender].add(fees[owner])).mul(deposited[msg.sender]).div(total);

        total = total.sub(deposited[msg.sender]);
        deposited[msg.sender] = 0;

        disputeToken.transfer(msg.sender, quantity);
    }
}
