// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "./PriceFeeds.sol";
import "./Randomness.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

error InvalidBetToken(uint8 token);
error InsufficientBetAmount(address sender, uint8 token, uint256 requiredBetInWei, uint256 betInWei);
error InsufficientAllowance(address sender, address token, uint256 amountInWei);
error InvalidCrosschainCaller(address caller);

abstract contract Predictions is PriceFeeds, Randomness, CCIPReceiver{

    struct Prediction{
        bytes32 squadHash;
        uint256 amountInWei;
        uint8 token;
        uint8 captain;
        uint8 viceCaptain;
        bool isRandom;
    }

    struct VrfTracker{
        uint256 gameId;
        address player;
    }

    uint256 public BET_AMOUNT_IN_USDC = 1 * 10 ** 5; // 6 decimals // 0.1 USDC
    mapping(uint256=>VrfTracker) public vrfRequests;
    mapping(uint256=>mapping(address=>Prediction)) public gameToPrediction;
    mapping(uint64=>address) public crosschainAddresses;

    address public immutable USDC_TOKEN;
    address public immutable LINK_TOKEN;

    constructor(address _vrfWrapper, address _ccipRouter, address _usdcToken, address _linkToken, AggregatorV3Interface[2] memory _priceFeeds, uint32 _vrfCallbackGaslimit) CCIPReceiver(_ccipRouter) PriceFeeds(_priceFeeds[0], _priceFeeds[1]) Randomness(_vrfWrapper, _vrfCallbackGaslimit) {
        USDC_TOKEN=_usdcToken;
        LINK_TOKEN=_linkToken;
    }

    modifier onlyAllowlisted(uint64 _selector, address _caller){
        if(crosschainAddresses[_selector]!=_caller) revert InvalidCrosschainCaller(_caller);
        _;
    }

    event BetPlaced(uint256 gameId, address caller, Prediction Prediction);
    event CrosschainAddressesSet(uint64[] destinationSelectors, address[] destinationAddresses); 
    event CrosschainReceived(bytes32 messageId);
    event BetAmountSet(uint256 amount);

    function setCrosschainAddresses(uint64[] memory _destinationSelectors, address[] memory _destinationAddresses) external onlyOwner {
         for(uint256 i=0; i<_destinationSelectors.length; i++) crosschainAddresses[_destinationSelectors[i]] = _destinationAddresses[i];
        emit CrosschainAddressesSet(_destinationSelectors, _destinationAddresses);
    }

    function _makeSquadAndPlaceBet(uint256 _gameId, bytes32 _squadHash, uint256 _amount, uint8 _token, uint8 _captain, uint8 _viceCaptain) internal virtual returns(uint256){

        uint256 _remainingValue = msg.value;

        if(_token == 0){
            _swapEthToUSDC(_amount);
            _remainingValue = msg.value - _amount;
        }
        else if(_token == 1) _swapLinkToUSDC(_amount);
        else if(_token == 2) _transferUsdc(_amount);
        else revert InvalidBetToken(_token);
        
        gameToPrediction[_gameId][msg.sender] = Prediction(_squadHash, _amount, _token, _captain, _viceCaptain, false);
        emit BetPlaced(_gameId,  msg.sender, gameToPrediction[_gameId][msg.sender]);

        return _remainingValue;
    }

    function _makeSquadAndPlaceBetRandom(uint256 _gameId, bytes32 _squadHash,  uint256 _amount, uint8 _token) internal virtual returns(uint256){
        
        uint256 _remainingValue = msg.value;
        if(_token == 0){
            _swapEthToUSDC(_amount);
            _remainingValue = msg.value - _amount;
        }
        else if(_token == 1) _swapLinkToUSDC(_amount);
        else if(_token == 2) _transferUsdc(_amount);
        else revert InvalidBetToken(_token);

        gameToPrediction[_gameId][msg.sender] = Prediction(_squadHash, _amount, _token, 12, 12, true);

        (uint256 _requestId, uint256 _requestPrice) = _requestRandomness();
        _remainingValue = _remainingValue - _requestPrice;
        vrfRequests[_requestId] = VrfTracker(_gameId, msg.sender);

        return _remainingValue;
    }

    function _swapEthToUSDC(uint256 _amountInWei) internal {
        uint256 _betValueInWei=getBetValue(BET_AMOUNT_IN_USDC, 0);
        if(_amountInWei < _betValueInWei) revert InsufficientBetAmount(msg.sender, 0, _betValueInWei, _amountInWei);
    }

    function _swapLinkToUSDC(uint256 _amountInWei) internal {
        if(IERC20(LINK_TOKEN).allowance(msg.sender, address(this)) < _amountInWei) revert InsufficientAllowance(msg.sender, LINK_TOKEN, _amountInWei);
        uint256 _betValueInWei=getBetValue(BET_AMOUNT_IN_USDC, 0);
        IERC20(LINK_TOKEN).transferFrom(msg.sender, address(this), _amountInWei);
        if(_amountInWei < _betValueInWei) revert InsufficientBetAmount(msg.sender, 1, _betValueInWei, _amountInWei);
    }

    function  _transferUsdc(uint256 _betAmountInWei) internal {
        if(IERC20(USDC_TOKEN).allowance(msg.sender, address(this)) < _betAmountInWei) revert InsufficientAllowance(msg.sender, USDC_TOKEN, _betAmountInWei);
        
        IERC20(USDC_TOKEN).transferFrom(msg.sender, address(this), _betAmountInWei);

        if(_betAmountInWei < BET_AMOUNT_IN_USDC) revert InsufficientBetAmount(msg.sender, 2, _betAmountInWei, _betAmountInWei);
    }

    function setBetAmountInUSDC(uint256 _amount) external onlyOwner {
        BET_AMOUNT_IN_USDC = _amount;
        emit BetAmountSet(_amount);
    }


}