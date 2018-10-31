//ONLY FOR V1

pragma solidity ^0.4.25;

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
    require(c / a == b);

    return c;
  }

  /**
  * @dev Integer division of two numbers truncating the quotient, reverts on division by zero.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b > 0); // Solidity only automatically asserts when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold

    return c;
  }

  /**
  * @dev Subtracts two numbers, reverts on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a);
    uint256 c = a - b;

    return c;
  }

  /**
  * @dev Adds two numbers, reverts on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a);

    return c;
  }

  /**
  * @dev Divides two numbers and returns the remainder (unsigned integer modulo),
  * reverts when dividing by zero.
  */
  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0);
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
    function getCrowdsourcer(bytes32 _payoutDistributionHash) public view returns (Token);
}

contract IReportingParticipant {
    function getSize() public view returns (uint256);
    function totalSupply() public view returns (uint256);
}

contract AugurDisputePool {
    using SafeMath for uint256;
    
    bool public needsClaimed;
    bool public txRun;
    address public txSender;
    mapping(address => uint256)[65536] public depositors;
    mapping(address => uint256)[65536] public depositorsFee;
    mapping(address => uint256)[65536] public depositorsMinusFees;
    
    //the tree - keep track of the total rep staked below each node, 16 children, 4 layers
    uint256 public total;
    uint256[16] public level1;
    uint256[256] public level2;
    uint256[4096] public level3;
    uint256[65536] public deposited;

    uint256 public totalFee;
    uint256[16] public level1Fee;
    uint256[256] public level2Fee;
    uint256[4096] public level3Fee;
    uint256[65536] public depositedFee;
    
    uint256 public totalMinusFees;
    uint256[16] public level1MinusFees;
    uint256[256] public level2MinusFees;
    uint256[4096] public level3MinusFees;
    uint256[65536] public depositedMinusFees;

    bool public feesPaidInDisputeTokens;

    bool public hasWinners;
    uint256 public winnerBoundary;
    
    mapping(address => uint256) public addresses;
    mapping(address => uint256) public feesInRep;
    mapping(address => uint256) public feesInDisputeTokens;
    
    address marketAddress;
    uint256[] payoutNumerators;
    bool invalid;
    address repAddress;
    bytes32 payoutDistributionHash;

    address public owner;

    constructor(address _owner, address _marketAddress, uint256[] _payoutNumerators, bool _invalid, address _repAddress) public {
        Market market = Market(_marketAddress);
        require(_repAddress == address(market.getReputationToken()));
        require(_payoutNumerators.length == market.getNumberOfOutcomes());
        owner = _owner;
        marketAddress = _marketAddress;
        payoutNumerators = _payoutNumerators;
        invalid = _invalid;
        repAddress = _repAddress;
        payoutDistributionHash = derivePayoutDistributionHash(payoutNumerators, invalid);
    }

    function depositRep(uint256 _fee, uint256 _quantity) public {
        Token rep = Token(repAddress);
        
        require(rep.allowance(msg.sender, this) >= _quantity);
        require(_fee <= 10000);
        require(_fee >= 1);
        require(needsClaimed == false);
        require(txRun == false);
        
        rep.transferFrom(msg.sender, this, _quantity);
        
        deposited[_fee] = deposited[_fee].add(_quantity);
        depositedFee[_fee] = depositedFee[_fee].add(_quantity.mul(_fee).div(uint256(uint256(10000))));
        depositedMinusFees[_fee] = deposited[_fee].sub(depositedFee[_fee]);
        
        uint256 lvl3fee = _fee.div(16);
        level3[lvl3fee] = level3[lvl3fee].add(_quantity);
        level3Fee[lvl3fee] = level3Fee[lvl3fee].add(_quantity.mul(_fee).div(uint256(10000)));
        level3MinusFees[lvl3fee] = level3[lvl3fee].sub(level3Fee[lvl3fee]);
        
        uint256 lvl2fee = lvl3fee.div(16);
        level2[lvl2fee] = level2[lvl2fee].add(_quantity);
        level2Fee[lvl2fee] = level2Fee[lvl2fee].add(_quantity.mul(_fee).div(uint256(10000)));
        level2MinusFees[lvl2fee] = level2[lvl2fee].sub(level2Fee[lvl2fee]);
        
        uint256 lvl1fee = lvl2fee.div(16);
        level1[lvl1fee] = level1[lvl1fee].add(_quantity);
        level1Fee[lvl1fee] = level1Fee[lvl1fee].add(_quantity.mul(_fee).div(uint256(10000)));
        level1MinusFees[lvl1fee] = level1[lvl1fee].sub(level1Fee[lvl1fee]);
        
        total = total.add(_quantity);
        totalFee = totalFee.add(_quantity.mul(_fee).div(uint256(10000)));
        totalMinusFees = total.sub(totalFee);
        
        depositors[_fee][msg.sender] = depositors[_fee][msg.sender].add(_quantity);
        depositorsFee[_fee][msg.sender] = depositorsFee[_fee][msg.sender].add(_quantity.mul(_fee).div(uint256(10000)));
        depositorsMinusFees[_fee][msg.sender] = depositors[_fee][msg.sender].sub(depositorsFee[_fee][msg.sender]);
        
        addresses[msg.sender] = addresses[msg.sender].add(_quantity);
    }
    
    function withdrawRep(uint256 _fee, uint256 _quantity) public {
        Token rep = Token(repAddress);
        
        require(needsClaimed == false);
        
        deposited[_fee] = deposited[_fee].sub(_quantity);
        depositedMinusFees[_fee] = depositedMinusFees[_fee].sub(_quantity.mul(uint256(10000).sub(_fee)).div(uint256(10000)));
        depositedFee[_fee] = deposited[_fee].sub(depositedMinusFees[_fee]);
        
        uint256 lvl3fee = _fee.div(16);
        level3[lvl3fee] = level3[lvl3fee].sub(_quantity);
        level3MinusFees[_fee] = level3MinusFees[lvl3fee].sub(_quantity.mul(uint256(10000).sub(_fee)).div(uint256(10000)));
        level3Fee[lvl3fee] = level3[lvl3fee].sub(level3MinusFees[_fee]);
        
        uint256 lvl2fee = lvl3fee.div(16);
        level2[lvl2fee] = level2[lvl2fee].sub(_quantity);
        level2MinusFees[_fee] = level2MinusFees[lvl2fee].sub(_quantity.mul(uint256(10000).sub(_fee)).div(uint256(10000)));
        level2Fee[lvl2fee] = level2[lvl2fee].sub(level2MinusFees[_fee]);
        
        uint256 lvl1fee = lvl2fee.div(16);
        level1[lvl1fee] = level1[lvl1fee].sub(_quantity);
        level1MinusFees[_fee] = level1MinusFees[lvl1fee].sub(_quantity.mul(uint256(10000).sub(_fee)).div(uint256(10000)));
        level1Fee[lvl1fee] = level1[lvl1fee].sub(level1MinusFees[_fee]);
        
        total = total.sub(_quantity);
        totalMinusFees = totalMinusFees.sub(_quantity.mul(uint256(10000).sub(_fee)).div(uint256(10000)));
        totalFee = total.sub(totalMinusFees);
        
        depositors[_fee][msg.sender] = depositors[_fee][msg.sender].sub(_quantity);
        depositorsMinusFees[_fee][msg.sender] = depositorsMinusFees[_fee][msg.sender].sub(_quantity.mul(uint256(10000).sub(_fee)).div(uint256(10000)));
        depositorsFee[_fee][msg.sender] = depositors[_fee][msg.sender].sub(depositorsMinusFees[_fee][msg.sender]);
        
        addresses[msg.sender] = addresses[msg.sender].sub(_quantity);
        
        rep.transfer(msg.sender, _quantity);
    }
    
    function derivePayoutDistributionHash(uint256[] _payoutNumerators, bool _invalid) internal view returns (bytes32) {
        Market market = Market(marketAddress);
        if(_invalid == true) {
            for(uint256 i = 0; i < _payoutNumerators.length; i++) {
                _payoutNumerators[i] = market.getNumTicks().div(market.getNumberOfOutcomes());
            }
        }
        bytes32 _payoutDistributionHash = market.derivePayoutDistributionHash(_payoutNumerators, _invalid);
        return _payoutDistributionHash;
    }
    
    function sendDispute(bool getPaidInDisputeTokens) public {
        Market market = Market(marketAddress);
        
        require(needsClaimed == false);
        require(txRun == false);
        
        //the amount of REP to send equals the max of this dispute round minus what's already in the dispute, minus 0.1 REP so as not to close out the round, saving a bit of gas
        uint256 quantity = market.getReportingParticipant(market.getNumParticipants() - 1).getSize().sub(market.getReportingParticipant(market.getNumParticipants() - 1).totalSupply()).sub(uint256(100000000000000000));
        
        //if what we have in the contract is less than what we want to send, send what we've got
        if(getPaidInDisputeTokens == true) {
            if(total < quantity) {
                quantity = total;
            }
            feesPaidInDisputeTokens = true;
        }else {
            uint256 totalMinusFee = total.sub(totalFee);
            if(totalMinusFee < quantity) {
                quantity = totalMinusFee;
            }
            feesPaidInDisputeTokens = false;
        }
        
        needsClaimed = true;
        txRun = true;
        
        market.contribute(payoutNumerators, invalid, quantity);
    }

    function claim() public {
        //cycle through tree, determine boundaries
        Market market = Market(marketAddress);
        
        require(needsClaimed == true);
        require(txRun == true);
        
        Token disputeToken = market.getCrowdsourcer(payoutDistributionHash);
        uint256 disputeTokenBalance = disputeToken.balanceOf(this);
        
        if(disputeTokenBalance > 0) {
            hasWinners = true;
            if(feesPaidInDisputeTokens == true) {
                findWinnerBoundaryFeeDisputeTokens(disputeTokenBalance);
            }else {
                findWinnerBoundaryFeeRepTokens(disputeTokenBalance);
            }
        }
        
        needsClaimed = false;
    }
    
    function findWinnerBoundaryFeeDisputeTokens(uint256 disputeTokenBalance) internal {
        uint256 cumulativeFee;
        uint256[2] memory lvl1;
        lvl1[0] = 0;
        for(uint256 i = level1.length.sub(1); i >= 0; i = i.sub(1)) {
            lvl1[0] = lvl1[0].add(level1[i]);
            cumulativeFee = cumulativeFee.add(level1Fee[i]);
            if(disputeTokenBalance <= lvl1[0]) {
                lvl1[1] = i;
                lvl1[0] = lvl1[0].sub(level1[i]);
                cumulativeFee = cumulativeFee.sub(level1Fee[i]);
                break;
            }
        }
        
        uint256[2] memory lvl2;
        lvl2[0] = lvl1[0];
        for(i = lvl1[1].add(1).mul(16).sub(1); i >= lvl1[1].mul(16); i = i.sub(1)) {
            lvl2[0] = lvl2[0].add(level2[i]);
            cumulativeFee = cumulativeFee.add(level2Fee[i]);
            if(disputeTokenBalance <= lvl2[0]) {
                lvl2[1] = i;
                lvl2[0] = lvl2[0].sub(level2[i]);
                cumulativeFee = cumulativeFee.sub(level2Fee[i]);
                break;
            }
        }
        
        cumulativeFee = findWinnerBoundaryFeeDisputeTokensPart2(disputeTokenBalance, cumulativeFee, lvl2);
        
        uint256 ownerFees = cumulativeFee.mul(5).div(100);
        feesInDisputeTokens[owner] = feesInDisputeTokens[owner].add(ownerFees);
        feesInDisputeTokens[txSender] = feesInDisputeTokens[txSender].add(cumulativeFee.sub(ownerFees));
    }
    
    function findWinnerBoundaryFeeDisputeTokensPart2(uint256 disputeTokenBalance, uint256 cumulativeFee, uint256[2] lvl2) internal returns (uint256) {
        uint256[2] memory lvl3;
        lvl3[0] = lvl2[0];
        for(uint256 i = lvl2[1].add(1).mul(16).sub(1); i >= lvl2[1].mul(16); i = i.sub(1)) {
            lvl3[0] = lvl3[0].add(level3[i]);
            cumulativeFee = cumulativeFee.add(level3Fee[i]);
            if(disputeTokenBalance <= lvl3[0]) {
                lvl3[1] = i;
                lvl3[0] = lvl3[0].sub(level3[i]);
                cumulativeFee = cumulativeFee.sub(level3Fee[i]);
                break;
            }
        }
        
        uint256[2] memory lvl4;
        lvl4[0] = lvl3[0];
        for(i = lvl3[1].add(1).mul(16).sub(1); i >= lvl3[1].mul(16); i = i.sub(1)) {
            lvl4[0] = lvl4[0].add(deposited[i]);
            cumulativeFee = cumulativeFee.add(depositedFee[i]);
            if(disputeTokenBalance <= lvl4[0]) {
                winnerBoundary = i;
                lvl4[0] = lvl4[0].sub(deposited[i]);
                cumulativeFee = cumulativeFee.sub(depositedFee[i]);
                cumulativeFee = cumulativeFee.add(disputeTokenBalance.sub(lvl4[0]).mul(i).div(depositedFee[i]).div(10000));
                break;
            }
        }
        
        return cumulativeFee;
    }
    
    function findWinnerBoundaryFeeRepTokens(uint256 disputeTokenBalance) internal {
        uint256 cumulativeFee;
        uint256[2] memory lvl1;
        lvl1[0] = 0;
        for(uint256 i = level1MinusFees.length.sub(1); i >= 0; i = i.sub(1)) {
            lvl1[0] = lvl1[0].add(level1MinusFees[i]);
            cumulativeFee = cumulativeFee.add(level1Fee[i]);
            if(disputeTokenBalance <= lvl1[0]) {
                lvl1[1] = i;
                lvl1[0] = lvl1[0].sub(level1MinusFees[i]);
                cumulativeFee = cumulativeFee.sub(level1Fee[i]);
                break;
            }
        }
        
        uint256[2] memory lvl2;
        lvl2[0] = lvl1[0];
        for(i = lvl1[1].add(1).mul(16).sub(1); i >= lvl1[1].mul(16); i = i.sub(1)) {
            lvl2[0] = lvl2[0].add(level2MinusFees[i]);
            cumulativeFee = cumulativeFee.add(level2Fee[i]);
            if(disputeTokenBalance <= lvl2[0]) {
                lvl2[1] = i;
                lvl2[0] = lvl2[0].sub(level2MinusFees[i]);
                cumulativeFee = cumulativeFee.sub(level2Fee[i]);
                break;
            }
        }
        
        cumulativeFee = findWinnerBoundaryFeeRepTokensPart2(disputeTokenBalance, cumulativeFee, lvl2);
        
        uint256 ownerFees = cumulativeFee.mul(5).div(100);
        feesInRep[owner] = feesInRep[owner].add(ownerFees);
        feesInRep[txSender] = feesInRep[txSender].add(cumulativeFee.sub(ownerFees));
    }
    
    function findWinnerBoundaryFeeRepTokensPart2(uint256 disputeTokenBalance, uint256 cumulativeFee, uint256[2] lvl2) internal returns (uint256) {
        uint256[2] memory lvl3;
        lvl3[0] = lvl2[0];
        for(uint256 i = lvl2[1].add(1).mul(16).sub(1); i >= lvl2[1].mul(16); i = i.sub(1)) {
            lvl3[0] = lvl3[0].add(level3MinusFees[i]);
            cumulativeFee = cumulativeFee.add(level3Fee[i]);
            if(disputeTokenBalance <= lvl3[0]) {
                lvl3[1] = i;
                lvl3[0] = lvl3[0].sub(level3MinusFees[i]);
                cumulativeFee = cumulativeFee.sub(level3Fee[i]);
                break;
            }
        }
        
        uint256[2] memory lvl4;
        lvl4[0] = lvl3[0];
        for(i = lvl3[1].add(1).mul(16).sub(1); i >= lvl3[1].mul(16); i = i.sub(1)) {
            lvl4[0] = lvl4[0].add(depositedMinusFees[i]);
            cumulativeFee = cumulativeFee.add(depositedFee[i]);
            if(disputeTokenBalance <= lvl4[0]) {
                winnerBoundary = i;
                lvl4[0] = lvl4[0].sub(depositedMinusFees[i]);
                cumulativeFee = cumulativeFee.sub(depositedFee[i]);
                cumulativeFee = cumulativeFee.add(disputeTokenBalance.sub(lvl4[0]).mul(i).div(depositedFee[i]).div(10000));
            }
        }
        
        return cumulativeFee;
    }

    function withdrawRepFees(address rep) public {
        uint256 f = feesInRep[msg.sender];
        feesInRep[msg.sender] = 0;
        Token r = Token(rep);
        r.transfer(msg.sender, f);
    }

    function withdrawDisputeFees(address dispute) public {
        uint256 f = feesInDisputeTokens[msg.sender];
        feesInDisputeTokens[msg.sender] = 0;
        Token d = Token(dispute);
        d.transfer(msg.sender, f);
    }

    function withdrawWinnings(uint256 _fee) public {
        require(txRun == true);
        require(needsClaimed == false);
        require(hasWinners == true);
        require(winnerBoundary <= _fee);
        
        Market market = Market(marketAddress);
        Token disputeToken = market.getCrowdsourcer(payoutDistributionHash);
        
        if(winnerBoundary < _fee) {
            uint256[3] memory quantity;
            quantity[0] = depositorsMinusFees[_fee][msg.sender];
            quantity[1] = depositors[_fee][msg.sender];
            quantity[2] = depositorsFee[_fee][msg.sender];
        }else {
            uint256 fees = feesInDisputeTokens[txSender];
            uint256 disputeTokenBalance = disputeToken.balanceOf(this);
            quantity[0] = disputeTokenBalance.sub(fees).mul(depositedMinusFees[_fee]).div(depositorsMinusFees[_fee][msg.sender]);
            quantity[1] = disputeTokenBalance.sub(fees).mul(deposited[_fee]).div(depositors[_fee][msg.sender]);
            quantity[2] = disputeTokenBalance.sub(fees).mul(depositedFee[_fee]).div(depositorsFee[_fee][msg.sender]);
        }
        addresses[msg.sender] = addresses[msg.sender].sub(quantity[1]);
        
        depositors[_fee][msg.sender] = 0;
        depositorsMinusFees[_fee][msg.sender] = 0;
        depositorsFee[_fee][msg.sender] = 0;
        
        deposited[_fee] = deposited[_fee].sub(quantity[1]);
        depositedMinusFees[_fee] = depositedMinusFees[_fee].sub(quantity[0]);
        depositedFee[_fee] = depositedFee[_fee].sub(quantity[2]);
        
        uint256 lvl3fee = _fee.div(16);
        level3[lvl3fee] = level3[lvl3fee].sub(quantity[1]);
        level3MinusFees[lvl3fee] = level3MinusFees[lvl3fee].sub(quantity[0]);
        level3Fee[lvl3fee] = level3Fee[lvl3fee].sub(quantity[2]);
        
        uint256 lvl2fee = lvl3fee.div(16);
        level2[lvl2fee] = level2[lvl2fee].sub(quantity[1]);
        level2MinusFees[lvl2fee] = level2MinusFees[lvl2fee].sub(quantity[0]);
        level2Fee[lvl2fee] = level2Fee[lvl2fee].sub(quantity[2]);
        
        uint256 lvl1fee = lvl2fee.div(16);
        level1[lvl1fee] = level1[lvl1fee].sub(quantity[1]);
        level1MinusFees[lvl1fee] = level1MinusFees[lvl1fee].sub(quantity[0]);
        level1Fee[lvl1fee] = level1Fee[lvl1fee].sub(quantity[2]);
        
        total = total.sub(quantity[1]);
        totalMinusFees = totalMinusFees.sub(quantity[0]);
        totalFee = totalFee.sub(quantity[2]);
        
        disputeToken.transfer(msg.sender, quantity[0]);
    }
}
