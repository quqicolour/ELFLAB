// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// /**
//  * @title LMSRPredictionMarket
//  * @dev 基于LMSR算法的二元预测市场，支持流动性管理和交易
//  */
// contract LMSRPredictionMarket {
//     using SafeERC20 for IERC20;
//     // 使用64.64定点数数学库处理小数运算
//     int128 private constant ONE_64x64 = 0x10000000000000000; // 1.0 in 64.64 fixed point
//     uint256 private constant PRECISION = 1e18;
//     uint256 private constant LN2 = 693147180559945309; // ln(2) * 1e18

//     IERC20 public usdcToken;

//     // 市场状态
//     enum MarketState {
//         OPEN,
//         CLOSED,
//         RESOLVED
//     }

//     // 结果选项
//     enum Outcome {
//         YES,
//         NO
//     }

//     // 市场信息
//     struct Market {
//         address creator;
//         string question;
//         uint256 closingTime;
//         uint256 resolutionTime;
//         MarketState state;
//         Outcome winningOutcome;
//         uint256 liquidityParameter; // b parameter in LMSR
//         uint256 totalLiquidityShares;
//         mapping(address => uint256) liquidityShares;
//         mapping(Outcome => uint256) outcomeShares;
//         mapping(address => mapping(Outcome => uint256)) userShares;
//     }

//     Market public market;

//     // 事件
//     event LiquidityAdded(
//         address indexed provider,
//         uint256 amount,
//         uint256 shares
//     );
//     event LiquidityRemoved(
//         address indexed provider,
//         uint256 amount,
//         uint256 shares
//     );
//     event SharesTraded(
//         address indexed trader,
//         Outcome outcome,
//         uint256 amount,
//         uint256 cost
//     );
//     event MarketResolved(Outcome winningOutcome);
//     event SharesRedeemed(
//         address indexed user,
//         Outcome outcome,
//         uint256 amount,
//         uint256 payout
//     );

//     constructor(
//         address _usdcTokenAddress,
//         string memory _question,
//         uint256 _closingTime,
//         uint256 _resolutionTime,
//         uint256 _initialLiquidity
//     ) {

//         usdcToken = IERC20(_usdcTokenAddress);

//         market.creator = msg.sender;
//         market.question = _question;
//         market.closingTime = _closingTime + block.timestamp;
//         market.resolutionTime = _resolutionTime + block.timestamp;
//         market.state = MarketState.OPEN;
//         market.liquidityParameter = _initialLiquidity;

//         // 初始化市场份额
//         market.outcomeShares[Outcome.YES] = 0;
//         market.outcomeShares[Outcome.NO] = 0;
//     }

//     /**
//      * @dev 添加流动性
//      */
//     function addLiquidity(uint256 amount) external {
//         require(market.state == MarketState.OPEN, "Market not open");
//         require(amount > 0, "Amount must be positive");

//         usdcToken.safeTransferFrom(msg.sender, address(this), amount);

//         uint256 shares;
//         if (market.totalLiquidityShares == 0) {
//             shares = amount;
//         } else {
//             shares =
//                 (amount * market.totalLiquidityShares) /
//                 getMarketLiquidity();
//         }

//         market.liquidityShares[msg.sender] += shares;
//         market.totalLiquidityShares += shares;
//         market.liquidityParameter += amount;

//         emit LiquidityAdded(msg.sender, amount, shares);
//     }

//     /**
//      * @dev 移除流动性
//      */
//     function removeLiquidity(uint256 shares) external {
//         require(market.state == MarketState.OPEN, "Market not open");
//         require(shares > 0, "Shares must be positive");
//         require(
//             market.liquidityShares[msg.sender] >= shares,
//             "Insufficient shares"
//         );

//         uint256 liquidityProportion = (shares * 1e18) /
//             market.totalLiquidityShares;
//         uint256 withdrawalAmount = (getMarketLiquidity() *
//             liquidityProportion) / 1e18;

//         // 更新状态
//         market.liquidityShares[msg.sender] -= shares;
//         market.totalLiquidityShares -= shares;
//         market.liquidityParameter =
//             (market.liquidityParameter * (market.totalLiquidityShares)) /
//             (market.totalLiquidityShares + shares);

//         // 转账
//         usdcToken.safeTransfer(msg.sender, withdrawalAmount);

//         emit LiquidityRemoved(msg.sender, withdrawalAmount, shares);
//     }

//     /**
//      * @dev 购买份额（交易）
//      */
//     function buyShares(Outcome outcome, uint256 amount) external payable {
//         require(market.state == MarketState.OPEN, "Market not open");
//         require(block.timestamp < market.closingTime, "Trading closed");
//         require(amount > 0, "Amount must be positive");

//         uint256 cost = calculateCost(outcome, amount);
//         usdcToken.safeTransferFrom(msg.sender, address(this), cost);

//         // 更新市场份额
//         market.outcomeShares[outcome] += amount;
//         market.userShares[msg.sender][outcome] += amount;

//         // 处理超额支付
//         if (msg.value > cost) {
//             payable(msg.sender).transfer(msg.value - cost);
//         }

//         emit SharesTraded(msg.sender, outcome, amount, cost);
//     }

//     /**
//      * @dev 出售份额
//      */
//     function sellShares(Outcome outcome, uint256 amount) external {
//         require(market.state == MarketState.OPEN, "Market not open");
//         require(block.timestamp < market.closingTime, "Trading closed");
//         require(amount > 0, "Amount must be positive");
//         require(
//             market.userShares[msg.sender][outcome] >= amount,
//             "Insufficient shares"
//         );

//         uint256 payout = calculatePayout(outcome, amount);

//         // 更新市场份额
//         market.outcomeShares[outcome] -= amount;
//         market.userShares[msg.sender][outcome] -= amount;

//         // 支付
//         usdcToken.safeTransfer(msg.sender, payout);

//         emit SharesTraded(msg.sender, outcome, amount, payout);
//     }

//     /**
//      * @dev 解析市场（设置获胜结果）
//      */
//     function resolveMarket(Outcome winningOutcome) external {
//         require(market.state == MarketState.OPEN, "Market not resolved");
//         require(block.timestamp >= market.closingTime, "Market not yet closed");
//         require(msg.sender == market.creator, "Only creator can resolve");

//         market.winningOutcome = winningOutcome;
//         market.state = MarketState.RESOLVED;

//         emit MarketResolved(winningOutcome);
//     }

//     /**
//      * @dev 兑换获胜份额
//      */
//     function redeemShares() external {
//         require(market.state == MarketState.RESOLVED, "Market not resolved");

//         uint256 yesShares = market.userShares[msg.sender][Outcome.YES];
//         uint256 noShares = market.userShares[msg.sender][Outcome.NO];
//         uint256 totalPayout = 0;

//         if (yesShares > 0) {
//             uint256 payout = calculateRedemption(Outcome.YES, yesShares);
//             totalPayout += payout;
//             market.userShares[msg.sender][Outcome.YES] = 0;
//             emit SharesRedeemed(msg.sender, Outcome.YES, yesShares, payout);
//         }

//         if (noShares > 0) {
//             uint256 payout = calculateRedemption(Outcome.NO, noShares);
//             totalPayout += payout;
//             market.userShares[msg.sender][Outcome.NO] = 0;
//             emit SharesRedeemed(msg.sender, Outcome.NO, noShares, payout);
//         }

//         if (totalPayout > 0) {
//             payable(msg.sender).transfer(totalPayout);
//         }
//     }

//     /**
//      * @dev LMSR成本函数计算
//      */
//     function calculateCost(
//         Outcome outcome,
//         uint256 amount
//     ) public view returns (uint256) {
//         uint256 b = market.liquidityParameter;
//         uint256 qYes = market.outcomeShares[Outcome.YES];
//         uint256 qNo = market.outcomeShares[Outcome.NO];

//         if (b == 0) return amount; // 初始情况

//         // C(q) = b * ln(e^(q_yes/b) + e^(q_no/b))
//         // cost = C(q + amount) - C(q)

//         uint256 newQYes = (outcome == Outcome.YES) ? qYes + amount : qYes;
//         uint256 newQNo = (outcome == Outcome.NO) ? qNo + amount : qNo;

//         uint256 currentCost = computeCostFunction(qYes, qNo, b);
//         uint256 newCost = computeCostFunction(newQYes, newQNo, b);

//         return newCost - currentCost;
//     }

//     /**
//      * @dev 计算卖出份额的支付
//      */
//     function calculatePayout(
//         Outcome outcome,
//         uint256 amount
//     ) public view returns (uint256) {
//         uint256 b = market.liquidityParameter;
//         uint256 qYes = market.outcomeShares[Outcome.YES];
//         uint256 qNo = market.outcomeShares[Outcome.NO];

//         require(
//             amount <= ((outcome == Outcome.YES) ? qYes : qNo),
//             "Insufficient market shares"
//         );

//         uint256 newQYes = (outcome == Outcome.YES) ? qYes - amount : qYes;
//         uint256 newQNo = (outcome == Outcome.NO) ? qNo - amount : qNo;

//         uint256 currentCost = computeCostFunction(qYes, qNo, b);
//         uint256 newCost = computeCostFunction(newQYes, newQNo, b);

//         return currentCost - newCost;
//     }

//     /**
//      * @dev 计算兑换金额
//      */
//     function calculateRedemption(
//         Outcome outcome,
//         uint256 amount
//     ) public view returns (uint256) {
//         require(market.state == MarketState.RESOLVED, "Market not resolved");

//         if (outcome == market.winningOutcome) {
//             return amount; // 获胜方1:1兑换
//         } else {
//             return 0; // 失败方无兑换
//         }
//     }

//     /**
//      * @dev 优化的LMSR成本函数计算
//      * C = b * ln(exp(q_yes/b) + exp(q_no/b))
//      * 使用数值稳定的计算方法
//      */
//     function computeCostFunction(
//         uint256 qYes, 
//         uint256 qNo, 
//         uint256 b
//     ) internal pure returns (uint256) {
//         if (b == 0) return 0;
        
//         // 数值稳定的计算方法：提取最大值
//         uint256 maxQ = qYes > qNo ? qYes : qNo;
//         uint256 minQ = qYes > qNo ? qNo : qYes;
        
//         // 如果差异太大，直接返回maxQ避免数值问题
//         if (maxQ-(minQ) > b*(10)) {
//             return maxQ;
//         }
        
//         // 使用: C = maxQ + b * ln(1 + exp((minQ - maxQ)/b))
//         // 这样避免了大数相减导致的数值不稳定
        
//         if (maxQ == minQ) {
//             // 两个数量相等时的特殊情况
//             return maxQ+(b*(LN2)/(PRECISION));
//         }
        
//         // 计算 (minQ - maxQ)/b，注意这是负数
//         // 我们使用 int256 来处理负数
//         int256 exponent = (int256(minQ) - int256(maxQ)) * int256(PRECISION) / int256(b);
        
//         // 计算 exp(exponent) = exp((minQ - maxQ)/b)
//         uint256 expVal = fixedExp(uint256(-exponent)); // 传入正数
        
//         // 计算 ln(1 + expVal)
//         uint256 logTerm = fixedLn(PRECISION+(expVal));
        
//         // C = maxQ + b * logTerm / PRECISION
//         return maxQ+(b*(logTerm)/(PRECISION));
//     }
    
//     /**
//      * @dev 计算LMSR价格
//      * p_i = exp(q_i/b) / (sum(exp(q_j/b)))
//      */
//     function computePrice(
//         uint256 qOutcome,
//         uint256 qYes,
//         uint256 qNo,
//         uint256 b
//     ) internal pure returns (uint256) {
//         if (b == 0) return PRECISION / 2; // 返回50%
        
//         uint256 maxQ = qYes > qNo ? qYes : qNo;
//         maxQ = maxQ > qOutcome ? maxQ : qOutcome;
        
//         // 数值稳定的计算方法
//         uint256 expYes = fixedExp(uint256((int256(qYes) - int256(maxQ)) * int256(PRECISION) / int256(b)));
//         uint256 expNo = fixedExp(uint256((int256(qNo) - int256(maxQ)) * int256(PRECISION) / int256(b)));
//         uint256 expOutcome = fixedExp(uint256((int256(qOutcome) - int256(maxQ)) * int256(PRECISION) / int256(b)));
        
//         uint256 sumExp = expYes+(expNo);
//         if (sumExp == 0) return 0;
        
//         return expOutcome*(PRECISION)/(sumExp);
//     }
    
//     /**
//      * @dev 定点指数函数 - 使用泰勒展开
//      * 仅适用于 x <= 10 * PRECISION
//      */
//     function fixedExp(uint256 x) internal pure returns (uint256) {
//         // 处理边界情况
//         if (x == 0) return PRECISION;
//         if (x > 10 * PRECISION) return type(uint256).max;
        
//         uint256 result = PRECISION;
//         uint256 term = PRECISION;
        
//         // 泰勒展开: e^x ≈ 1 + x + x^2/2! + x^3/3! + x^4/4!
//         for (uint256 i = 1; i <= 8; i++) {
//             term = term*(x)/(i)/(PRECISION);
//             result = result+(term);
            
//             // 如果项变得太小，提前终止
//             if (term < 1e10) break;
//         }
        
//         return result;
//     }
    
//     /**
//      * @dev 定点自然对数 - 使用迭代法
//      * 仅适用于 x >= PRECISION/10 && x <= 10 * PRECISION
//      */
//     function fixedLn(uint256 x) internal pure returns (uint256) {
//         require(x > 0, "ln of non-positive");
        
//         // 归一化到 [1, 2] 范围内
//         uint256 scaledX = x;
//         uint256 log2 = 0;
        
//         // 通过除以2来归一化，并记录除以2的次数
//         while (scaledX > 2 * PRECISION) {
//             scaledX = scaledX / 2;
//             log2 = log2+(PRECISION / 2); // ln(2) ≈ 0.693, 但我们用0.5作为近似
//         }
//         while (scaledX < PRECISION) {
//             scaledX = scaledX * 2;
//             log2 = log2-(PRECISION / 2);
//         }
        
//         // 现在 scaledX 在 [PRECISION, 2*PRECISION] 范围内
//         // 使用 ln(x) = 2 * artanh((x-1)/(x+1)) 的近似
//         uint256 z = scaledX-(PRECISION);
//         uint256 denominator = scaledX+(PRECISION);
//         uint256 ratio = z*(PRECISION)/(denominator);
        
//         uint256 result = ratio;
//         uint256 term = ratio;
//         uint256 ratioSquared = ratio*(ratio)/(PRECISION);
        
//         // 泰勒展开
//         for (uint256 i = 1; i <= 10; i++) {
//             term = term*(ratioSquared)/(PRECISION);
//             uint256 newResult = result+(term/(2 * i + 1));
//             if (newResult == result) break; // 收敛
//             result = newResult;
//         }
        
//         result = result*(2);
//         return result+(log2);
//     }

//     /**
//      * @dev 获取当前市场价格（概率）
//      */
//     function getCurrentPrice(Outcome outcome) public view returns (uint256) {
//         uint256 b = market.liquidityParameter;
//         uint256 qYes = market.outcomeShares[Outcome.YES];
//         uint256 qNo = market.outcomeShares[Outcome.NO];

//         if (b == 0) return 0.5 * 1e18; // 初始价格50%

//         // p = exp(q/b) / (exp(q_yes/b) + exp(q_no/b))
//         uint256 expYes = exp((qYes * 1e18) / b);
//         uint256 expNo = exp((qNo * 1e18) / b);
//         uint256 denominator = expYes + expNo;

//         if (outcome == Outcome.YES) {
//             return (expYes * 1e18) / denominator;
//         } else {
//             return (expNo * 1e18) / denominator;
//         }
//     }

//     /**
//      * @dev 获取市场流动性
//      */
//     function getMarketLiquidity() public view returns (uint256) {
//         return address(this).balance;
//     }

//     /**
//      * @dev 获取用户信息
//      */
//     function getUserInfo(
//         address user
//     )
//         external
//         view
//         returns (
//             uint256 liquidityShares,
//             uint256 yesShares,
//             uint256 noShares,
//             uint256 totalValue
//         )
//     {
//         liquidityShares = market.liquidityShares[user];
//         yesShares = market.userShares[user][Outcome.YES];
//         noShares = market.userShares[user][Outcome.NO];

//         // 计算总价值（流动性份额价值 + 市场份额价值）
//         uint256 liquidityValue = (liquidityShares * getMarketLiquidity()) /
//             market.totalLiquidityShares;
//         uint256 sharesValue = calculatePayout(Outcome.YES, yesShares) +
//             calculatePayout(Outcome.NO, noShares);

//         totalValue = liquidityValue + sharesValue;
//     }

//     // 数学辅助函数（简化实现）
//     function exp(uint256 x) internal pure returns (uint256) {
//         // 简化指数函数实现 - 实际应用中应使用更精确的算法
//         if (x == 0) return 1e18;
//         if (x > 10 * 1e18) return type(uint256).max;
//         return ((1e18 + x + (x * x) / (2 * 1e18)) * 1e18) / 1e18;
//     }

//     function ln(uint256 x) internal pure returns (uint256) {
//         // 简化自然对数实现
//         require(x > 0, "ln of non-positive");
//         if (x == 1e18) return 0;
//         return ((x - 1e18) * 1e18) / x; // 一阶近似
//     }

//     function ln2() internal pure returns (uint256) {
//         return 693147180559945309; // ln(2) * 1e18
//     }
// }
