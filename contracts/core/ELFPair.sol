// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import './ELFERC20.sol';
import '../interfaces/IELFPair.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IELFFactory.sol';
import '../interfaces/IELFCallee.sol';
import '../interfaces/IELFNft.sol';

import "@openzeppelin/contracts/utils/math/Math.sol";

contract ELFPair is IELFPair, ELFERC20 {

  bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

  uint32 private constant MIN_LIQUIDITY = 1000;
  uint32 private constant FEE_DENOMINATOR = 100000;
  address private factory;
  
  address private token0;
  address private token1;
  address private elfNFT;

  // uint public constant MAX_FEE_PERCENT = 2000; // = 2%

  uint112 private reserve0;           // uses single storage slot, accessible via getReserves
  uint112 private reserve1;           // uses single storage slot, accessible via getReserves
  uint16 private initialized;
  uint16 private unlocked = 1;

  uint256 private precisionMultiplier0;
  uint256 private precisionMultiplier1;

  uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

  modifier lock() {
    require(unlocked == 1, 'ELF: LOCKED');
    unlocked = 0;
    _;
    unlocked = 1;
  }

  constructor(address _elf) ELFERC20() {
    factory = msg.sender;
    elfNFT = _elf;
  }

  function getReserves() public view returns (
    uint112 _reserve0, 
    uint112 _reserve1, 
    uint16 _token0FeePercent, 
    uint16 _token1FeePercent
  ) {
    _reserve0 = reserve0;
    _reserve1 = reserve1;
    if(_checkValidElf()){
      // 50%
      _token0FeePercent = _getPoolInfo().token0FeePercent / 2;
      _token1FeePercent = _getPoolInfo().token1FeePercent / 2;
    }else{
      _token0FeePercent = _getPoolInfo().token0FeePercent;
      _token1FeePercent = _getPoolInfo().token1FeePercent;
    }
  }

  function _safeTransfer(address token, address to, uint value) private {
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))),"ELF: TRANSFER_FAILED");
  }

  // called once by the factory at time of deployment
  function initialize(address _token0, address _token1) external {
    require(msg.sender == factory && initialized == 0);
    // sufficient check
    token0 = _token0;
    token1 = _token1;

    precisionMultiplier0 = 10 ** _getDecimals(_token0);
    precisionMultiplier1 = 10 ** _getDecimals(_token1);

    initialized = 1;
  }

  // update reserves
  function _update(uint256 balance0, uint256 balance1) private {
    require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "ELF: OVERFLOW");
    reserve0 = uint112(balance0);
    reserve1 = uint112(balance1);
    emit Sync(uint112(balance0), uint112(balance1));
  }

  // this low-level function should be called from a contract which performs important safety checks
  function mint(address to) external lock returns (uint256 liquidity) {
    (uint112 _reserve0, uint112 _reserve1,,) = getReserves();
    // gas savings
    uint256 balance0 = _getBalance(token0, address(this));
    uint256 balance1 = _getBalance(token1, address(this));
    uint256 amount0 = balance0 - _reserve0;
    uint256 amount1 = balance1 - _reserve1;

    // gas savings, must be defined here since totalSupply can update in _mintFee
    if (totalSupply == 0) {
      liquidity = Math.sqrt(amount0 * amount1) - MIN_LIQUIDITY;
      _mint(address(0), MIN_LIQUIDITY);
      // permanently lock the first MINIMUM_LIQUIDITY tokens
    } else {
      liquidity = Math.min(amount0 * totalSupply / _reserve0, amount1 * totalSupply / _reserve1);
    }
    require(liquidity > 0, "ELF: INSUFFICIENT_LIQUIDITY_MINTED");
    _mint(to, liquidity);

    _update(balance0, balance1);
    // reserve0 and reserve1 are up-to-date
    emit Mint(msg.sender, amount0, amount1);
  }

  // this low-level function should be called from a contract which performs important safety checks
  function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
    uint256 balance0 = _getBalance(token0, address(this));
    uint256 balance1 = _getBalance(token1, address(this));
    uint256 liquidity = balanceOf[address(this)];

    uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
    amount0 = liquidity * balance0 / _totalSupply; // using balances ensures pro-rata distribution
    amount1 = liquidity * balance1 / _totalSupply; // using balances ensures pro-rata distribution
    require(amount0 > 0 && amount1 > 0, "ELF: INSUFFICIENT_LIQUIDITY_BURNED");
    _burn(address(this), liquidity);
    _safeTransfer(token0, to, amount0);
    _safeTransfer(token1, to, amount1);
    balance0 = _getBalance(token0, address(this));
    balance1 = _getBalance(token1, address(this));

    _update(balance0, balance1);
    emit Burn(msg.sender, amount0, amount1, to);
  }

  // this low-level function should be called from a contract which performs important safety checks
  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external {
    TokensData memory tokensData = TokensData({
      token0: token0,
      token1: token1,
      amount0Out: amount0Out,
      amount1Out: amount1Out,
      balance0: 0,
      balance1: 0,
      remainingFee0: 0,
      remainingFee1: 0
    });
    _swap(tokensData, to, data);
  }

  function _swap(TokensData memory tokensData, address to, bytes memory data) internal lock {
    require(tokensData.amount0Out > 0 || tokensData.amount1Out > 0, "ELF: INSUFFICIENT_OUTPUT_AMOUNT");

    (uint112 _reserve0, uint112 _reserve1, uint16 _token0FeePercent, uint16 _token1FeePercent) = getReserves();
    require(tokensData.amount0Out < _reserve0 && tokensData.amount1Out < _reserve1, "ELF: INSUFFICIENT_LIQUIDITY");

    {
      require(to != tokensData.token0 && to != tokensData.token1, "ELF: INVALID_TO");
      //send receive
      // optimistically transfer tokens
      if (tokensData.amount0Out > 0) _safeTransfer(tokensData.token0, to, tokensData.amount0Out);
      // optimistically transfer tokens
      if (tokensData.amount1Out > 0) _safeTransfer(tokensData.token1, to, tokensData.amount1Out);
      if (data.length > 0) IELFCallee(to).elfV2Call(msg.sender, tokensData.amount0Out, tokensData.amount1Out, data);
      tokensData.balance0 = _getBalance(tokensData.token0, address(this));
      tokensData.balance1 = _getBalance(tokensData.token1, address(this));
    }

    uint256 amount0In = tokensData.balance0 > _reserve0 - tokensData.amount0Out ? tokensData.balance0 - (_reserve0 - tokensData.amount0Out) : 0;
    uint256 amount1In = tokensData.balance1 > _reserve1 - tokensData.amount1Out ? tokensData.balance1 - (_reserve1 - tokensData.amount1Out) : 0;
    require(amount0In > 0 || amount1In > 0, "ELF: INSUFFICIENT_INPUT_AMOUNT");

    tokensData.remainingFee0 = amount0In * _token0FeePercent / FEE_DENOMINATOR;
    tokensData.remainingFee1 = amount1In * _token1FeePercent / FEE_DENOMINATOR;

    {// scope for stable fees management
      //0.3%
      uint256 fee;
      //0.05%
      uint256 luckyFee;
      address feeReceiver = _getPoolInfo().feeReceiver;
      if(feeReceiver != address(0)){
        address luckyPool = _getPoolInfo().luckyPool;
        if (amount0In > 0) {
          fee = amount0In * _token0FeePercent / FEE_DENOMINATOR;
          if(_getPoolInfo().luckyPoolFeePercent != 0){
            luckyFee = amount0In * _getPoolInfo().luckyPoolFeePercent / FEE_DENOMINATOR;
          }
          tokensData.remainingFee0 = tokensData.remainingFee0 - fee - luckyFee;
          //Official fee
          _safeTransfer(tokensData.token0, feeReceiver, fee);
          if(luckyPool != address(0)){
            _safeTransfer(tokensData.token0, luckyPool, luckyFee);
          }
        }
        if (amount1In > 0) {
          fee = amount1In * _token1FeePercent / FEE_DENOMINATOR;
          if(_getPoolInfo().luckyPoolFeePercent != 0){
            luckyFee = amount1In * _getPoolInfo().luckyPoolFeePercent / FEE_DENOMINATOR;
          }
          tokensData.remainingFee1 = tokensData.remainingFee1 - fee - luckyFee;
          //Official fee
          _safeTransfer(tokensData.token1, feeReceiver, fee);
          if(luckyPool != address(0)){
            _safeTransfer(tokensData.token1, luckyPool, luckyFee);
          }
        }
      }

      // read just tokens balance
      if (amount0In > 0) tokensData.balance0 = _getBalance(tokensData.token0, address(this));
      if (amount1In > 0) tokensData.balance1 = _getBalance(tokensData.token1, address(this));
    }
    {// scope for reserve{0,1}Adjusted, avoids stack too deep errors
      uint256 balance0Adjusted = tokensData.balance0 - tokensData.remainingFee0;
      uint256 balance1Adjusted = tokensData.balance1 - tokensData.remainingFee1;
      require(_k(balance0Adjusted, balance1Adjusted) >= _k(uint256(_reserve0), uint256(_reserve1)));
    }
    _update(tokensData.balance0, tokensData.balance1);
    emit Swap(msg.sender, amount0In, amount1In, tokensData.amount0Out, tokensData.amount1Out, to);
  }

  function _k(uint256 balance0, uint256 balance1) private view returns (uint256) {
    if (_getPoolInfo().stableSwap) {
      uint256 _x = balance0 * 1e18 / precisionMultiplier0;
      uint256 _y = balance1 * 1e18 / precisionMultiplier1;
      uint256 _a = _x * _y / 1e18;
      uint256 _b = _x * _x / 1e18 + _y * _y / 1e18;
      return  _a * _b / 1e18; // x3y+y3x >= k
    }else{
      return balance0 * balance1;
    }
  }

  function _get_y(uint256 x0, uint256 xy, uint256 y) private pure returns (uint256) {
    for (uint256 i = 0; i < 255; i++) {
      uint256 y_prev = y;
      uint256 k = _f(x0, y);
      if (k < xy) {
        uint256 dy = (xy - k) * 1e18 / _d(x0, y);
        y = y + dy;
      } else {
        uint256 dy = (k - xy) * 1e18 / _d(x0, y);
        y = y - dy;
      }
      if (y > y_prev) {
        if (y - y_prev <= 1) {
          return y;
        }
      } else {
        if (y_prev - y <= 1) {
          return y;
        }
      }
    }
    return y;
  }

  function _f(uint256 x0, uint256 y) private pure returns (uint256) {
    return x0 * (y * y / 1e18 * y / 1e18) / 1e18 + (x0 * x0 / 1e18 * x0 / 1e18) * y / 1e18;
  }

  function _d(uint256 x0, uint256 y) private pure returns (uint256) {
    return 3 * x0 * (y * y / 1e18) / 1e18 + (x0 * x0 / 1e18 * x0 / 1e18);
  }

  function _getDecimals(address token) private view returns(uint8 _decimals){
    _decimals = IERC20(token).decimals();
  }

  function _getBalance(address token, address checker) private view returns(uint256 _thisBalance){
    _thisBalance = IERC20(token).balanceOf(checker);
  }

  function _getPoolInfo() private view returns (IELFFactory.PoolInfo memory thisPoolInfo) {
    thisPoolInfo = IELFFactory(factory).getPoolInfo(address(this));
  }

  function _checkValidElf() private view returns (bool state) {
    if(IELFNft(elfNFT).valid(tx.origin)){
      state = true;
    }
  }

  function _getAmountOut(
    uint256 amountIn, 
    address tokenIn, 
    uint256 _reserve0, 
    uint256 _reserve1, 
    uint256 feePercent
  ) internal view returns (uint256) {
    uint16 luckyPoolFeePercent = _getPoolInfo().luckyPoolFeePercent;
    uint256 newFeePercent;
    if(_checkValidElf()){
      newFeePercent = feePercent / 2;
    }
    if (_getPoolInfo().stableSwap) {
      amountIn = amountIn - amountIn * (newFeePercent + luckyPoolFeePercent) / FEE_DENOMINATOR; // remove fee from amount received
      uint256 xy = _k(_reserve0, _reserve1);
      _reserve0 = _reserve0 * precisionMultiplier0 * 1e18 / precisionMultiplier0;
      _reserve1 = _reserve1 * precisionMultiplier1 * 1e18 / precisionMultiplier1;

      (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
      amountIn = tokenIn == token0 ? amountIn * 1e18 / precisionMultiplier0 : amountIn * 1e18 / precisionMultiplier1;
      uint256 y = reserveB - _get_y(amountIn + reserveA, xy, reserveB);
      return y * (tokenIn == token0 ? precisionMultiplier1 : precisionMultiplier0) / 1e18;
    } else {
      (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
      amountIn = amountIn * (FEE_DENOMINATOR - newFeePercent - luckyPoolFeePercent);
      return (amountIn * reserveB) / (reserveA * FEE_DENOMINATOR + amountIn);
    }
  }

  function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256) {
    uint16 feePercent = tokenIn == token0 ? _getPoolInfo().token0FeePercent : _getPoolInfo().token1FeePercent;
    return _getAmountOut(amountIn, tokenIn, uint256(reserve0), uint256(reserve1), feePercent);
  }

  // force balances to match reserves
  function skim(address to) external lock {
    address _token0 = token0;
    // gas savings
    address _token1 = token1;
    // gas savings
    _safeTransfer(_token0, to, _getBalance(_token0, address(this)) - (reserve0));
    _safeTransfer(_token1, to, _getBalance(_token1, address(this)) - (reserve1));
  }

  // force reserves to match balances
  function sync() external lock {
    uint256 token0Balance = _getBalance(token0, address(this));
    uint256 token1Balance = _getBalance(token1, address(this));
    require(token0Balance != 0 && token1Balance != 0, "ELF: liquidity ratio not initialized");
    _update(token0Balance, token1Balance);
  }

}