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
    
    //market => (round => (payoutDistributionHash => feeTree))
    mapping(address => mapping(uint256 => mapping(bytes32 => bool))) public needsClaimed;
    mapping(address => mapping(uint256 => mapping(bytes32 => bool))) public txRun;
    mapping(address => mapping(uint256 => mapping(bytes32 => address))) public txSender;
    mapping(address => mapping(uint256 => mapping(bytes32 => mapping(address => uint256)[65536]))) public depositors;
    mapping(address => mapping(uint256 => mapping(bytes32 => mapping(address => uint256)[65536]))) public depositorsFee;
    mapping(address => mapping(uint256 => mapping(bytes32 => mapping(address => uint256)[65536]))) public depositorsMinusFees;
    
    //the tree - keep track of the total rep staked below each node, 16 children, 4 layers
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256))) public total;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[16]))) public level1;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[256]))) public level2;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[4096]))) public level3;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[65536]))) public deposited;

    mapping(address => mapping(uint256 => mapping(bytes32 => uint256))) public totalFee;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[16]))) public level1Fee;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[256]))) public level2Fee;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[4096]))) public level3Fee;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[65536]))) public depositedFee;
    
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256))) public totalMinusFees;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[16]))) public level1MinusFees;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[256]))) public level2MinusFees;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[4096]))) public level3MinusFees;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256[65536]))) public depositedMinusFees;

    mapping(address => mapping(uint256 => mapping(bytes32 => bool))) public feesPaidInDisputeTokens;

    mapping(address => mapping(uint256 => mapping(bytes32 => bool))) public hasWinners;
    mapping(address => mapping(uint256 => mapping(bytes32 => uint256))) public winnerBoundary;
    
    mapping(address => uint256) public addresses;
    mapping(address => mapping(address => uint256)) public feesInRep;
    mapping(address => mapping(address => uint256)) public feesInDisputeTokens;

    address public owner;

    constructor(address _owner) public {
        owner = _owner;
    }

//{{Do I need both the market and the dispute?  Figure that out}}
//ensure that len(_payoutNumerators) is the same as the number of outcomes in the market
//don't allow deposits after transaction has been made for a given dispute -> figure out a way to delineate dispute rounds?
    function depositRep(address _market, uint256 _roundNumber, uint256[] _payoutNumerators, bool _invalid, uint256 _fee, uint256 _quantity) public {
        Market market = Market(_market);
        Token rep = market.getReputationToken();
        require(rep.allowance(msg.sender, this) >= _quantity);
        require(_payoutNumerators.length == market.getNumberOfOutcomes());
        require(_fee <= 10000);
        require(_fee >= 1);
        bytes32 payoutDistributionHash = derivePayoutDistributionHash(_market, _payoutNumerators, _invalid);
        require(needsClaimed[_market][_roundNumber][payoutDistributionHash] == false);
        require(txRun[_market][_roundNumber][payoutDistributionHash] == false);
        rep.transferFrom(msg.sender, this, _quantity);
        deposited[_market][_roundNumber][payoutDistributionHash][_fee] = deposited[_market][_roundNumber][payoutDistributionHash][_fee].add(_quantity);
        depositedFee[_market][_roundNumber][payoutDistributionHash][_fee] = depositedFee[_market][_roundNumber][payoutDistributionHash][_fee].add(_quantity.mul(_fee).div(10000));
        depositedMinusFees[_market][_roundNumber][payoutDistributionHash][_fee] = deposited[_market][_roundNumber][payoutDistributionHash][_fee].sub(depositedFee[_market][_roundNumber][payoutDistributionHash][_fee]);
        uint256 lvl3fee = _fee.div(16);
        level3[_market][_roundNumber][payoutDistributionHash][lvl3fee] = level3[_market][_roundNumber][payoutDistributionHash][lvl3fee].add(_quantity);
        level3Fee[_market][_roundNumber][payoutDistributionHash][lvl3fee] = level3Fee[_market][_roundNumber][payoutDistributionHash][lvl3fee].add(_quantity.mul(_fee).div(10000));
        level3MinusFees[_market][_roundNumber][payoutDistributionHash][lvl3fee] = level3[_market][_roundNumber][payoutDistributionHash][lvl3fee].sub(level3Fee[_market][_roundNumber][payoutDistributionHash][lvl3fee]);
        uint256 lvl2fee = lvl3fee.div(16);
        level2[_market][_roundNumber][payoutDistributionHash][lvl2fee] = level2[_market][_roundNumber][payoutDistributionHash][lvl2fee].add(_quantity);
        level2Fee[_market][_roundNumber][payoutDistributionHash][lvl2fee] = level2Fee[_market][_roundNumber][payoutDistributionHash][lvl2fee].add(_quantity.mul(_fee).div(10000));
        level2MinusFees[_market][_roundNumber][payoutDistributionHash][lvl2fee] = level2[_market][_roundNumber][payoutDistributionHash][lvl2fee].sub(level2Fee[_market][_roundNumber][payoutDistributionHash][lvl2fee]);
        uint256 lvl1fee = lvl2fee.div(16);
        level1[_market][_roundNumber][payoutDistributionHash][lvl1fee] = level1[_market][_roundNumber][payoutDistributionHash][lvl1fee].add(_quantity);
        level1Fee[_market][_roundNumber][payoutDistributionHash][lvl1fee] = level1Fee[_market][_roundNumber][payoutDistributionHash][lvl1fee].add(_quantity.mul(_fee).div(10000));
        level1MinusFees[_market][_roundNumber][payoutDistributionHash][lvl1fee] = level1[_market][_roundNumber][payoutDistributionHash][lvl1fee].sub(level1Fee[_market][_roundNumber][payoutDistributionHash][lvl1fee]);
        total[_market][_roundNumber][payoutDistributionHash] = total[_market][_roundNumber][payoutDistributionHash].add(_quantity);
        totalFee[_market][_roundNumber][payoutDistributionHash] = totalFee[_market][_roundNumber][payoutDistributionHash].add(_quantity.mul(_fee).div(10000));
        totalMinusFees[_market][_roundNumber][payoutDistributionHash] = total[_market][_roundNumber][payoutDistributionHash].sub(totalFee[_market][_roundNumber][payoutDistributionHash]);
        depositors[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender] = depositors[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender].add(_quantity);
        depositorsFee[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender] = depositorsFee[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender].add(_quantity.mul(_fee).div(10000));
        depositorsMinusFees[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender] = depositors[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender].sub(depositorsFee[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender]);
        addresses[msg.sender] = addresses[msg.sender].add(_quantity);
    }
    
    function withdrawRep(address _market, uint256 _roundNumber, uint256[] _payoutNumerators, bool _invalid, uint256 _fee, uint256 _quantity) public {
        Market market = Market(_market);
        bytes32 payoutDistributionHash = derivePayoutDistributionHash(_market, _payoutNumerators, _invalid);
        require(needsClaimed[_market][_roundNumber][payoutDistributionHash] == false);
        deposited[_market][_roundNumber][payoutDistributionHash][_fee] = deposited[_market][_roundNumber][payoutDistributionHash][_fee].sub(_quantity);
        depositedMinusFees[_market][_roundNumber][payoutDistributionHash][_fee] = depositedMinusFees[_market][_roundNumber][payoutDistributionHash][_fee].sub(_quantity.mul(uint256(10000).sub(_fee)).div(10000));
        depositedFee[_market][_roundNumber][payoutDistributionHash][_fee] = deposited[_market][_roundNumber][payoutDistributionHash][_fee].sub(depositedMinusFees[_market][_roundNumber][payoutDistributionHash][_fee]);
        uint256 lvl3fee = _fee.div(16);
        level3[_market][_roundNumber][payoutDistributionHash][lvl3fee] = level3[_market][_roundNumber][payoutDistributionHash][lvl3fee].sub(_quantity);
        level3MinusFees[_market][_roundNumber][payoutDistributionHash][_fee] = level3MinusFees[_market][_roundNumber][payoutDistributionHash][lvl3fee].sub(_quantity.mul(uint256(10000).sub(_fee)).div(10000));
        level3Fee[_market][_roundNumber][payoutDistributionHash][lvl3fee] = level3[_market][_roundNumber][payoutDistributionHash][lvl3fee].sub(level3MinusFees[_market][_roundNumber][payoutDistributionHash][_fee]);
        uint256 lvl2fee = lvl3fee.div(16);
        level2[_market][_roundNumber][payoutDistributionHash][lvl2fee] = level2[_market][_roundNumber][payoutDistributionHash][lvl2fee].sub(_quantity);
        level2MinusFees[_market][_roundNumber][payoutDistributionHash][_fee] = level2MinusFees[_market][_roundNumber][payoutDistributionHash][lvl2fee].sub(_quantity.mul(uint256(10000).sub(_fee)).div(10000));
        level2Fee[_market][_roundNumber][payoutDistributionHash][lvl2fee] = level2[_market][_roundNumber][payoutDistributionHash][lvl2fee].sub(level2MinusFees[_market][_roundNumber][payoutDistributionHash][_fee]);
        uint256 lvl1fee = lvl2fee.div(16);
        level1[_market][_roundNumber][payoutDistributionHash][lvl1fee] = level1[_market][_roundNumber][payoutDistributionHash][lvl1fee].sub(_quantity);
        level1MinusFees[_market][_roundNumber][payoutDistributionHash][_fee] = level1MinusFees[_market][_roundNumber][payoutDistributionHash][lvl1fee].sub(_quantity.mul(uint256(10000).sub(_fee)).div(10000));
        level1Fee[_market][_roundNumber][payoutDistributionHash][lvl1fee] = level1[_market][_roundNumber][payoutDistributionHash][lvl1fee].sub(level1MinusFees[_market][_roundNumber][payoutDistributionHash][_fee]);
        total[_market][_roundNumber][payoutDistributionHash] = total[_market][_roundNumber][payoutDistributionHash].sub(_quantity);
        totalMinusFees[_market][_roundNumber][payoutDistributionHash] = totalMinusFees[_market][_roundNumber][payoutDistributionHash].sub(_quantity.mul(uint256(10000).sub(_fee)).div(10000));
        totalFee[_market][_roundNumber][payoutDistributionHash] = total[_market][_roundNumber][payoutDistributionHash].sub(totalMinusFees[_market][_roundNumber][payoutDistributionHash]);
        depositors[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender] = depositors[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender].sub(_quantity);
        depositorsMinusFees[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender] = depositorsMinusFees[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender].sub(_quantity.mul(uint256(10000).sub(_fee)).div(10000));
        depositorsFee[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender] = depositors[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender].sub(depositorsMinusFees[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender]);
        addresses[msg.sender] = addresses[msg.sender].sub(_quantity);
        Token rep = market.getReputationToken();
        rep.transfer(msg.sender, _quantity);
    }
    
    function derivePayoutDistributionHash(address _market, uint256[] _payoutNumerators, bool _invalid) internal view returns (bytes32) {
        Market market = Market(_market);
        if(_invalid == true) {
            for(uint256 i = 0; i < _payoutNumerators.length; i++) {
                _payoutNumerators[i] = market.getNumTicks().div(market.getNumberOfOutcomes());
            }
        }
        bytes32 payoutDistributionHash = market.derivePayoutDistributionHash(_payoutNumerators, _invalid);
        return payoutDistributionHash;
    }
    
    function sendDispute(address _market, uint256[] _payoutNumerators, bool _invalid, bool getPaidInDisputeTokens) public {
        Market market = Market(_market);
        uint256 roundNumber = market.getNumParticipants();
        bytes32 payoutDistributionHash = derivePayoutDistributionHash(_market, _payoutNumerators, _invalid);
        require(needsClaimed[_market][roundNumber][payoutDistributionHash] == false);
        require(txRun[_market][roundNumber][payoutDistributionHash] == false);
        uint256 quantity = market.getReportingParticipant(roundNumber - 1).getSize().sub(market.getReportingParticipant(roundNumber - 1).totalSupply()).sub(uint256(100000000000000000));
        if(getPaidInDisputeTokens == true) {
            if(total[_market][roundNumber][payoutDistributionHash] < quantity) {
                quantity = total[_market][roundNumber][payoutDistributionHash];
            }
            feesPaidInDisputeTokens[_market][roundNumber][payoutDistributionHash] = true;
        }else {
            uint256 totalMinusFee = total[_market][roundNumber][payoutDistributionHash].sub(totalFee[_market][roundNumber][payoutDistributionHash]);
            if(totalMinusFee < quantity) {
                quantity = totalMinusFee;
            }
            feesPaidInDisputeTokens[_market][roundNumber][payoutDistributionHash] = false;
        }
        needsClaimed[_market][roundNumber][payoutDistributionHash] = true;
        txRun[_market][roundNumber][payoutDistributionHash] = true;
        market.contribute(_payoutNumerators, _invalid, quantity);
    }

    function claim(address _market, uint256 _roundNumber, uint256[] _payoutNumerators, bool _invalid) public {
        //cycle through tree, determine boundaries
        Market market = Market(_market);
        bytes32 payoutDistributionHash = derivePayoutDistributionHash(_market, _payoutNumerators, _invalid);
        require(needsClaimed[_market][_roundNumber][payoutDistributionHash] == true);
        require(txRun[_market][_roundNumber][payoutDistributionHash] == true);
        Token disputeToken = market.getCrowdsourcer(payoutDistributionHash);
        uint256 disputeTokenBalance = disputeToken.balanceOf(this);
        if(disputeTokenBalance > 0) {
            hasWinners[_market][_roundNumber][payoutDistributionHash] = true;
            if(feesPaidInDisputeTokens[_market][_roundNumber][payoutDistributionHash] == true) {
                findWinnerBoundaryFeeDisputeTokens(_market, _roundNumber, payoutDistributionHash, disputeTokenBalance, address(disputeToken));
            }else {
                findWinnerBoundaryFeeRepTokens(_market, _roundNumber, payoutDistributionHash, disputeTokenBalance, address(market.getReputationToken));
            }
        }
        //determine fees, give to executor, creator

        //set claim to false
        needsClaimed[_market][_roundNumber][payoutDistributionHash] = false;
    }
    
    function findWinnerBoundaryFeeDisputeTokens(address _market, uint256 _roundNumber, bytes32 payoutDistributionHash, uint256 disputeTokenBalance, address disputeTokens) internal {
        uint256 cumulativeFee;
        cumulativeFee = findWinnerBoundaryFeeDisputeTokensPart1(_market, _roundNumber, payoutDistributionHash, disputeTokenBalance, cumulativeFee);
        uint256 ownerFees = cumulativeFee.mul(5).div(100);
        feesInDisputeTokens[owner][disputeTokens] = feesInDisputeTokens[owner][disputeTokens].add(ownerFees);
        feesInDisputeTokens[txSender[_market][_roundNumber][payoutDistributionHash]][disputeTokens] = feesInDisputeTokens[txSender[_market][_roundNumber][payoutDistributionHash]][disputeTokens].add(cumulativeFee.sub(ownerFees));
    }
    
    function findWinnerBoundaryFeeDisputeTokensPart1(address _market, uint256 _roundNumber, bytes32 payoutDistributionHash, uint256 disputeTokenBalance, uint256 cumulativeFee) internal returns (uint256) {
        uint256[2] memory lvl1;
        lvl1[0] = 0;
        for(uint256 i = level1[_market][_roundNumber][payoutDistributionHash].length.sub(1); i >= 0; i = i.sub(1)) {
            lvl1[0] = lvl1[0].add(level1[_market][_roundNumber][payoutDistributionHash][i]);
            cumulativeFee = cumulativeFee.add(level1Fee[_market][_roundNumber][payoutDistributionHash][i]);
            if(disputeTokenBalance <= lvl1[0]) {
                lvl1[1] = i;
                lvl1[0] = lvl1[0].sub(level1[_market][_roundNumber][payoutDistributionHash][i]);
                cumulativeFee = cumulativeFee.sub(level1Fee[_market][_roundNumber][payoutDistributionHash][i]);
                break;
            }
        }
        uint256[2] memory lvl2;
        lvl2[0] = lvl1[0];
        for(i = lvl1[1].add(1).mul(16).sub(1); i >= lvl1[1].mul(16); i = i.sub(1)) {
            lvl2[0] = lvl2[0].add(level2[_market][_roundNumber][payoutDistributionHash][i]);
            cumulativeFee = cumulativeFee.add(level2Fee[_market][_roundNumber][payoutDistributionHash][i]);
            if(disputeTokenBalance <= lvl2[0]) {
                lvl2[1] = i;
                lvl2[0] = lvl2[0].sub(level2[_market][_roundNumber][payoutDistributionHash][i]);
                cumulativeFee = cumulativeFee.sub(level2Fee[_market][_roundNumber][payoutDistributionHash][i]);
                break;
            }
        }
        cumulativeFee = findWinnerBoundaryFeeDisputeTokensPart2(_market, _roundNumber, payoutDistributionHash, disputeTokenBalance, cumulativeFee, lvl2);
        return cumulativeFee;
    }
    
    function findWinnerBoundaryFeeDisputeTokensPart2(address _market, uint256 _roundNumber, bytes32 payoutDistributionHash, uint256 disputeTokenBalance, uint256 cumulativeFee, uint256[2] lvl2) internal returns (uint256) {
        uint256[2] memory lvl3;
        lvl3[0] = lvl2[0];
        for(uint256 i = lvl2[1].add(1).mul(16).sub(1); i >= lvl2[1].mul(16); i = i.sub(1)) {
            lvl3[0] = lvl3[0].add(level3[_market][_roundNumber][payoutDistributionHash][i]);
            cumulativeFee = cumulativeFee.add(level3Fee[_market][_roundNumber][payoutDistributionHash][i]);
            if(disputeTokenBalance <= lvl3[0]) {
                lvl3[1] = i;
                lvl3[0] = lvl3[0].sub(level3[_market][_roundNumber][payoutDistributionHash][i]);
                cumulativeFee = cumulativeFee.sub(level3Fee[_market][_roundNumber][payoutDistributionHash][i]);
                break;
            }
        }
        uint256[2] memory lvl4;
        lvl4[0] = lvl3[0];
        for(i = lvl3[1].add(1).mul(16).sub(1); i >= lvl3[1].mul(16); i = i.sub(1)) {
            lvl4[0] = lvl4[0].add(deposited[_market][_roundNumber][payoutDistributionHash][i]);
            cumulativeFee = cumulativeFee.add(depositedFee[_market][_roundNumber][payoutDistributionHash][i]);
            if(disputeTokenBalance <= lvl4[0]) {
                winnerBoundary[_market][_roundNumber][payoutDistributionHash] = i;
                lvl4[0] = lvl4[0].sub(deposited[_market][_roundNumber][payoutDistributionHash][i]);
                cumulativeFee = cumulativeFee.sub(depositedFee[_market][_roundNumber][payoutDistributionHash][i]);
                cumulativeFee = cumulativeFee.add(disputeTokenBalance.sub(lvl4[0]).mul(i).div(depositedFee[_market][_roundNumber][payoutDistributionHash][i]).div(10000));
                break;
            }
        }
        return cumulativeFee;
    }
    
    function findWinnerBoundaryFeeRepTokens(address _market, uint256 _roundNumber, bytes32 payoutDistributionHash, uint256 disputeTokenBalance, address repAddress) internal {
        uint256 cumulativeFee;
        cumulativeFee = findWinnerBoundaryFeeRepTokensPart1(_market, _roundNumber, payoutDistributionHash, disputeTokenBalance, cumulativeFee);
        uint256 ownerFees = cumulativeFee.mul(5).div(100);
        feesInRep[owner][repAddress] = feesInRep[owner][repAddress].add(ownerFees);
        feesInRep[txSender[_market][_roundNumber][payoutDistributionHash]][repAddress] = feesInRep[txSender[_market][_roundNumber][payoutDistributionHash]][repAddress].add(cumulativeFee.sub(ownerFees));
    }
    
    function findWinnerBoundaryFeeRepTokensPart1(address _market, uint256 _roundNumber, bytes32 payoutDistributionHash, uint256 disputeTokenBalance, uint256 cumulativeFee) internal returns (uint256) {
        uint256[2] memory lvl1;
        lvl1[0] = 0;
        for(uint256 i = level1MinusFees[_market][_roundNumber][payoutDistributionHash].length.sub(1); i >= 0; i = i.sub(1)) {
            lvl1[0] = lvl1[0].add(level1MinusFees[_market][_roundNumber][payoutDistributionHash][i]);
            cumulativeFee = cumulativeFee.add(level1Fee[_market][_roundNumber][payoutDistributionHash][i]);
            if(disputeTokenBalance <= lvl1[0]) {
                lvl1[1] = i;
                lvl1[0] = lvl1[0].sub(level1MinusFees[_market][_roundNumber][payoutDistributionHash][i]);
                cumulativeFee = cumulativeFee.sub(level1Fee[_market][_roundNumber][payoutDistributionHash][i]);
                break;
            }
        }
        uint256[2] memory lvl2;
        lvl2[0] = lvl1[0];
        for(i = lvl1[1].add(1).mul(16).sub(1); i >= lvl1[1].mul(16); i = i.sub(1)) {
            lvl2[0] = lvl2[0].add(level2MinusFees[_market][_roundNumber][payoutDistributionHash][i]);
            cumulativeFee = cumulativeFee.add(level2Fee[_market][_roundNumber][payoutDistributionHash][i]);
            if(disputeTokenBalance <= lvl2[0]) {
                lvl2[1] = i;
                lvl2[0] = lvl2[0].sub(level2MinusFees[_market][_roundNumber][payoutDistributionHash][i]);
                cumulativeFee = cumulativeFee.sub(level2Fee[_market][_roundNumber][payoutDistributionHash][i]);
                break;
            }
        }
        cumulativeFee = findWinnerBoundaryFeeRepTokensPart2(_market, _roundNumber, payoutDistributionHash, disputeTokenBalance, cumulativeFee, lvl2);
        return cumulativeFee;
    }
    
    function findWinnerBoundaryFeeRepTokensPart2(address _market, uint256 _roundNumber, bytes32 payoutDistributionHash, uint256 disputeTokenBalance, uint256 cumulativeFee, uint256[2] lvl2) internal returns (uint256) {
        uint256[2] memory lvl3;
        lvl3[0] = lvl2[0];
        for(uint256 i = lvl2[1].add(1).mul(16).sub(1); i >= lvl2[1].mul(16); i = i.sub(1)) {
            lvl3[0] = lvl3[0].add(level3MinusFees[_market][_roundNumber][payoutDistributionHash][i]);
            cumulativeFee = cumulativeFee.add(level3Fee[_market][_roundNumber][payoutDistributionHash][i]);
            if(disputeTokenBalance <= lvl3[0]) {
                lvl3[1] = i;
                lvl3[0] = lvl3[0].sub(level3MinusFees[_market][_roundNumber][payoutDistributionHash][i]);
                cumulativeFee = cumulativeFee.sub(level3Fee[_market][_roundNumber][payoutDistributionHash][i]);
                break;
            }
        }
        uint256[2] memory lvl4;
        lvl4[0] = lvl3[0];
        for(i = lvl3[1].add(1).mul(16).sub(1); i >= lvl3[1].mul(16); i = i.sub(1)) {
            lvl4[0] = lvl4[0].add(depositedMinusFees[_market][_roundNumber][payoutDistributionHash][i]);
            cumulativeFee = cumulativeFee.add(depositedFee[_market][_roundNumber][payoutDistributionHash][i]);
            if(disputeTokenBalance <= lvl4[0]) {
                winnerBoundary[_market][_roundNumber][payoutDistributionHash] = i;
                lvl4[0] = lvl4[0].sub(depositedMinusFees[_market][_roundNumber][payoutDistributionHash][i]);
                cumulativeFee = cumulativeFee.sub(depositedFee[_market][_roundNumber][payoutDistributionHash][i]);
                cumulativeFee = cumulativeFee.add(disputeTokenBalance.sub(lvl4[0]).mul(i).div(depositedFee[_market][_roundNumber][payoutDistributionHash][i]).div(10000));
            }
        }
        return cumulativeFee;
    }

    function withdrawRepFees(address rep) public {
        uint256 f = feesInRep[msg.sender][rep];
        feesInRep[msg.sender][rep] = 0;
        Token r = Token(rep);
        r.transfer(msg.sender, f);
    }

    function withdrawDisputeFees(address dispute) public {
        uint256 f = feesInDisputeTokens[msg.sender][dispute];
        feesInDisputeTokens[msg.sender][dispute] = 0;
        Token d = Token(dispute);
        d.transfer(msg.sender, f);
    }

    function withdrawWinnings(address _market, uint256 _roundNumber, uint256[] _payoutNumerators, bool _invalid, uint256 _fee) public {
        bytes32 payoutDistributionHash = derivePayoutDistributionHash(_market, _payoutNumerators, _invalid);
        require(txRun[_market][_roundNumber][payoutDistributionHash] == true);
        require(needsClaimed[_market][_roundNumber][payoutDistributionHash] == false);
        require(hasWinners[_market][_roundNumber][payoutDistributionHash] == true);
        require(winnerBoundary[_market][_roundNumber][payoutDistributionHash] <= _fee);
        Market market = Market(_market);
        Token disputeToken = market.getCrowdsourcer(payoutDistributionHash);
        if(winnerBoundary[_market][_roundNumber][payoutDistributionHash] < _fee) {
            uint256[3] memory quantity;
            quantity[0] = depositorsMinusFees[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender];
            quantity[1] = depositors[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender];
            quantity[2] = depositorsFee[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender];
        }else {
            uint256 fees = feesInDisputeTokens[txSender[_market][_roundNumber][payoutDistributionHash]][address(disputeToken)];
            uint256 disputeTokenBalance = disputeToken.balanceOf(this);
            quantity[0] = disputeTokenBalance.sub(fees).mul(depositedMinusFees[_market][_roundNumber][payoutDistributionHash][_fee]).div(depositorsMinusFees[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender]);
            quantity[1] = disputeTokenBalance.sub(fees).mul(deposited[_market][_roundNumber][payoutDistributionHash][_fee]).div(depositors[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender]);
            quantity[2] = disputeTokenBalance.sub(fees).mul(depositedFee[_market][_roundNumber][payoutDistributionHash][_fee]).div(depositorsFee[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender]);
        }
        decrementDuringWithdrawWinnings(_market, _roundNumber, payoutDistributionHash, _fee, quantity[0], quantity[1], quantity[2]);
        disputeToken.transfer(msg.sender, quantity[0]);
    }
    
    function decrementDuringWithdrawWinnings(address _market, uint256 _roundNumber, bytes32 payoutDistributionHash, uint256 _fee, uint256 quantity, uint256 quantityWithFee, uint256 quantityFee) internal {
        addresses[msg.sender] = addresses[msg.sender].sub(quantityWithFee);
        depositors[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender] = 0;
        depositorsMinusFees[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender] = 0;
        depositorsFee[_market][_roundNumber][payoutDistributionHash][_fee][msg.sender] = 0;
        deposited[_market][_roundNumber][payoutDistributionHash][_fee] = deposited[_market][_roundNumber][payoutDistributionHash][_fee].sub(quantityWithFee);
        depositedMinusFees[_market][_roundNumber][payoutDistributionHash][_fee] = depositedMinusFees[_market][_roundNumber][payoutDistributionHash][_fee].sub(quantity);
        depositedFee[_market][_roundNumber][payoutDistributionHash][_fee] = depositedFee[_market][_roundNumber][payoutDistributionHash][_fee].sub(quantityFee);
        uint256 lvl3fee = _fee.div(16);
        level3[_market][_roundNumber][payoutDistributionHash][lvl3fee] = level3[_market][_roundNumber][payoutDistributionHash][lvl3fee].sub(quantityWithFee);
        level3MinusFees[_market][_roundNumber][payoutDistributionHash][lvl3fee] = level3MinusFees[_market][_roundNumber][payoutDistributionHash][lvl3fee].sub(quantity);
        level3Fee[_market][_roundNumber][payoutDistributionHash][lvl3fee] = level3Fee[_market][_roundNumber][payoutDistributionHash][lvl3fee].sub(quantityFee);
        uint256 lvl2fee = lvl3fee.div(16);
        level2[_market][_roundNumber][payoutDistributionHash][lvl2fee] = level2[_market][_roundNumber][payoutDistributionHash][lvl2fee].sub(quantityWithFee);
        level2MinusFees[_market][_roundNumber][payoutDistributionHash][lvl2fee] = level2MinusFees[_market][_roundNumber][payoutDistributionHash][lvl2fee].sub(quantity);
        level2Fee[_market][_roundNumber][payoutDistributionHash][lvl2fee] = level2Fee[_market][_roundNumber][payoutDistributionHash][lvl2fee].sub(quantityFee);
        uint256 lvl1fee = lvl2fee.div(16);
        level1[_market][_roundNumber][payoutDistributionHash][lvl1fee] = level1[_market][_roundNumber][payoutDistributionHash][lvl1fee].sub(quantityWithFee);
        level1MinusFees[_market][_roundNumber][payoutDistributionHash][lvl1fee] = level1MinusFees[_market][_roundNumber][payoutDistributionHash][lvl1fee].sub(quantity);
        level1Fee[_market][_roundNumber][payoutDistributionHash][lvl1fee] = level1Fee[_market][_roundNumber][payoutDistributionHash][lvl1fee].sub(quantityFee);
        total[_market][_roundNumber][payoutDistributionHash] = total[_market][_roundNumber][payoutDistributionHash].sub(quantityWithFee);
        totalMinusFees[_market][_roundNumber][payoutDistributionHash] = totalMinusFees[_market][_roundNumber][payoutDistributionHash].sub(quantity);
        totalFee[_market][_roundNumber][payoutDistributionHash] = totalFee[_market][_roundNumber][payoutDistributionHash].sub(quantityFee);
    }

    function changeOwner(address _newOwner) public {
        owner = _newOwner;
    }
}
