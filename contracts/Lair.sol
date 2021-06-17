// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

/*

    ███████╗██████╗  █████╗ ███╗   ██╗██╗  ██╗███████╗███╗   ██╗███████╗████████╗███████╗██╗███╗   ██╗
    ██╔════╝██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝██╔════╝████╗  ██║██╔════╝╚══██╔══╝██╔════╝██║████╗  ██║
    █████╗  ██████╔╝███████║██╔██╗ ██║█████╔╝ █████╗  ██╔██╗ ██║███████╗   ██║   █████╗  ██║██╔██╗ ██║
    ██╔══╝  ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗ ██╔══╝  ██║╚██╗██║╚════██║   ██║   ██╔══╝  ██║██║╚██╗██║
    ██║     ██║  ██║██║  ██║██║ ╚████║██║  ██╗███████╗██║ ╚████║███████║   ██║   ███████╗██║██║ ╚████║
    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚══════╝╚═╝╚═╝  ╚═══╝
                                                                      
    Website: https://frankenstein.finance/
    twitter: https://twitter.com/FrankenDefi
*/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IFarm.sol";
import "./interfaces/IXRouter02.sol";
import "./interfaces/IHelp.sol";

contract Lair is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Address token
    IERC20 public token;
    // entrance fee
    uint256 public entranceFeeFactor;
    // 100 = 1%
    uint256 constant entranceFeeFactorMax = 10000;
    // 4% is the max entrance fee. LL = lowerlimit
    uint256 constant entranceFeeFactorLL = 9600;
    // withdraw fee
    uint256 public withdrawFeeFactor;
    // 100 = 1%
    uint256 public constant withdrawFeeFactorMax = 10000;
    // 1% is the max withdraw fee. LL = lowerlimit
    uint256 public constant withdrawFeeFactorLL = 9900;
    // 20%
    uint256 public buyBackRate = 2000; 
    // 100 = 1%
    uint256 public constant buyBackRateMax = 10000;
    // 10%
    uint256 public controllerFee = 1000;
    // 100 = 1%
    uint256 public constant controllerFeeMax = 10000;
    // 1%
    uint256 public reservesFee = 1000;
    // 100 = 1%
    uint256 public constant reservesFeeMax = 10000;
    // Dev address
    address public devAddress = 0xFfcdC72285a0AbA0AC2192c5E93eA774826ABC7f;
    // Reserves address
    address public reservesAddress = 0x3F413f92ea77960aD26632B0C9d8a7dF935Eb1D4;
    // BuyBack address
    address public buyAddress = 0x7a2C37c92Dd0f419793fD7A01035aA96596659BF;
    // Tokens deposited in the lair
    uint256 public totalDeposited;

    address public constant buyBackAddress = 0x000000000000000000000000000000000000dEaD;
    address public wbnbAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public NATIVEAddress = 0x129e6d84c6CAb9b0c2F37aD1D14a9fe2E59DAb09;
    address public farmContractAddress; // address of farm, eg, PCS, Thugs etc.
    uint256 public pid; // pid of pool in farmContractAddress
    address public wantAddress;
    address public token0Address;
    address public token1Address;
    address public earnedAddress;
    address public uniRouterAddress; // uniswap, pancakeswap etc
    address public buybackRouterAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    uint256 public routerDeadlineDuration = 300;  // Set on global level, could be passed to functions via arguments  

    address[] public earnedToNATIVEPath;
    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public token0ToEarnedPath;
    address[] public token1ToEarnedPath;
    address[] public earnedToWantPath;
    address[] public earnedToWBNBPath;
    address[] public WBNBToNATIVEPath;

    bool public isSingleVault;
    bool public isAutoComp;
    bool public isCakeBased;

    constructor(
        string memory _name, 
        string memory _alias, 
        IERC20 _token, 
        uint256 _entranceFeeFactor, 
        uint256 _withdrawFeeFactor, 
        address _farmContractAddress,
        uint256 _pid,
        address _token0Address,
        address _token1Address,
        address _earnedAddress,
        address _uniRouterAddress,
        bool _isSingleVault,
        bool _isAutoComp,
        bool _isCakeBased
    ) ERC20(_name, _alias) public {
        require(_entranceFeeFactor >= entranceFeeFactorLL, "!safe - too low");
        require(_entranceFeeFactor <= entranceFeeFactorMax, "!safe - too high");
        require(_withdrawFeeFactor >= withdrawFeeFactorLL, "!safe - too low");
        require(_withdrawFeeFactor <= withdrawFeeFactorMax, "!safe - too high");
        token = _token;
        entranceFeeFactor = _entranceFeeFactor;
        withdrawFeeFactor = _withdrawFeeFactor;
        farmContractAddress = _farmContractAddress;
        pid = _pid;
        wantAddress = address(_token);
        earnedAddress = _earnedAddress;
        uniRouterAddress = _uniRouterAddress;
        isSingleVault = _isSingleVault;
        isAutoComp = _isAutoComp;
        isCakeBased = _isCakeBased;

        if (isAutoComp) {
            if (!isSingleVault) {
                token0Address = _token0Address;
                token1Address = _token1Address;
            }

            earnedToNATIVEPath = [earnedAddress, wbnbAddress, NATIVEAddress];
            if (wbnbAddress == earnedAddress) {
                earnedToNATIVEPath = [wbnbAddress, NATIVEAddress];
            }

            earnedToToken0Path = [earnedAddress, wbnbAddress, token0Address];
            if (wbnbAddress == token0Address) {
                earnedToToken0Path = [earnedAddress, wbnbAddress];
            }

            earnedToToken1Path = [earnedAddress, wbnbAddress, token1Address];
            if (wbnbAddress == token1Address) {
                earnedToToken1Path = [earnedAddress, wbnbAddress];
            }

            token0ToEarnedPath = [token0Address, wbnbAddress, earnedAddress];
            if (wbnbAddress == token0Address) {
                token0ToEarnedPath = [wbnbAddress, earnedAddress];
            }

            token1ToEarnedPath = [token1Address, wbnbAddress, earnedAddress];
            if (wbnbAddress == token1Address) {
                token1ToEarnedPath = [wbnbAddress, earnedAddress];
            }

            earnedToWantPath = [earnedAddress, wbnbAddress, wantAddress];
            if (wbnbAddress == wantAddress) {
                earnedToWantPath = [earnedAddress, wantAddress];
            }

            earnedToWBNBPath = [earnedAddress, wbnbAddress];
            WBNBToNATIVEPath = [wbnbAddress, NATIVEAddress];            

        }

    }

    // reinvest harvested amount
    function farm() public nonReentrant {
        _farm();
    }    

    function _farm() internal {
        require(isAutoComp, "!isAutoComp");
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        totalDeposited = totalDeposited.add(wantAmt);
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);
        if(isCakeBased){
            IFarm(farmContractAddress).enterStaking(wantAmt);
        } else {
            IFarm(farmContractAddress).deposit(pid, wantAmt);
        }
    }

    // Enter the lair. Pay some Token. Earn some Lair.
    function enter(uint256 _tokenAmount) external nonReentrant {
        uint256 totalToken = totalDeposited;
        uint256 totalLair = totalSupply();
        uint256 _tokenAmountSender = _tokenAmount.mul(entranceFeeFactor).div(entranceFeeFactorMax);
        uint256 _tokenAmountFee = _tokenAmount.sub(_tokenAmountSender);
        if (totalLair == 0) {
            _mint(msg.sender, _tokenAmount);
        } else {
            uint256 lairAmount = _tokenAmountSender.mul(totalLair).div(totalToken);
            _mint(msg.sender, lairAmount);
        }
        token.transferFrom(msg.sender, address(this), _tokenAmount);
        if(_tokenAmountFee > 0 && totalLair > 0){
            token.transfer(buyAddress, _tokenAmountFee.div(2));
            token.transfer(devAddress, _tokenAmountFee.div(4));
            token.transfer(reservesAddress, _tokenAmountFee.div(4));
        }
        if (isAutoComp) {
            _farm();
        } else {
            totalDeposited = totalDeposited.add(token.balanceOf(address(this)));
        }
        if(totalLair > 0){
            _earn();
        }
    }

    // Leave the lair. Claim back your Token.
    function leave(uint256 _lairAmount) external nonReentrant {
        uint256 totalLair = totalSupply();
        uint256 tokenAmount = _lairAmount.mul(totalDeposited).div(totalLair);
        _burn(msg.sender, _lairAmount);
        tokenAmount = tokenAmount.mul(withdrawFeeFactor).div(withdrawFeeFactorMax);
        if (isAutoComp) {
            if(isCakeBased){
                IFarm(farmContractAddress).leaveStaking(tokenAmount);
            } else {
                IFarm(farmContractAddress).withdraw(pid, tokenAmount);
            }
        }
        IERC20(wantAddress).safeTransfer(msg.sender, tokenAmount); 
        totalDeposited = totalDeposited.sub(tokenAmount);
        _earn();
    }

    // Burn lairs
    function burn(uint256 _lairAmount) external nonReentrant {
        _burn(msg.sender, _lairAmount);
    }

    // returns the total amount of Tokens an address has in the contract including fees earned
    function TokenBalance(address _account) external view returns (uint256 tokenAmount_) {
        uint256 lairAmount = balanceOf(_account);
        uint256 totalLair = totalSupply();
        tokenAmount_ = lairAmount.mul(totalDeposited).div(totalLair);
    }

    //returns how much Tokens someone gets for depositing lair
    function LairForToken(uint256 _lairAmount) external view returns (uint256 tokenAmount_) {
        uint256 totalLair = totalSupply();
        tokenAmount_ = _lairAmount.mul(totalDeposited).div(totalLair);
    }

    //returns how much Lair someone gets for depositing Token
    function TokenForLair(uint256 _tokenAmount) public view returns (uint256 lairAmount_) {
        uint256 totalToken = totalDeposited;
        uint256 totalLair = totalSupply();
        if (totalLair == 0 || totalToken == 0) {
            lairAmount_ = _tokenAmount;
        }
        else {
            lairAmount_ = _tokenAmount.mul(totalLair).div(totalToken);
        }
    }

    // Entrance fee allocation
    function setEntranceFeeFactor(uint256 _entranceFeeFactor) public onlyOwner {
        require(_entranceFeeFactor >= entranceFeeFactorLL, "!safe - too low");
        require(_entranceFeeFactor <= entranceFeeFactorMax, "!safe - too high");
        entranceFeeFactor = _entranceFeeFactor;
    }

    // Withdraw fee allocation
    function setWithdrawFeeFactor(uint256 _withdrawFeeFactor) public onlyOwner {
        require(_withdrawFeeFactor >= withdrawFeeFactorLL, "!safe - too low");
        require(_withdrawFeeFactor <= withdrawFeeFactorMax, "!safe - too high");
        withdrawFeeFactor = _withdrawFeeFactor;
    }

    // 1. Harvest farm tokens
    // 2. Converts farm tokens into want tokens
    // 3. Deposits want tokens
    function earn() public nonReentrant {
        require(isAutoComp, "!isAutoComp");
        _earn();
    }

    function _earn() internal {
        // Harvest farm tokens
        if(isCakeBased){
            IFarm(farmContractAddress).leaveStaking(0);
        } else {
            IFarm(farmContractAddress).withdraw(pid, 0);
        }

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        earnedAmt = distributeFees(earnedAmt);
        earnedAmt = distributeReserves(earnedAmt);
        earnedAmt = buyBack(earnedAmt);

        if (isSingleVault) {
            if (earnedAddress != wantAddress) {
                IERC20(earnedAddress).safeIncreaseAllowance(
                    uniRouterAddress,
                    earnedAmt
                );

                // Swap earned to want
                IXRouter02(uniRouterAddress)
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    earnedAmt,
                    0,
                    earnedToWantPath,
                    address(this),
                    now + routerDeadlineDuration
                );
            }
            _farm();
            return;
        }

        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            earnedAmt
        );

        if (earnedAddress != token0Address) {
            // Swap half earned to token0
            IXRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                earnedAmt.div(2),
                0,
                earnedToToken0Path,
                address(this),
                now + routerDeadlineDuration
            );
        }

        if (earnedAddress != token1Address) {
            // Swap half earned to token1
            IXRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                earnedAmt.div(2),
                0,
                earnedToToken1Path,
                address(this),
                now + routerDeadlineDuration
            );
        }

        // Get want tokens, ie. add liquidity
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token0Amt > 0 && token1Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );
            IXRouter02(uniRouterAddress).addLiquidity(
                token0Address,
                token1Address,
                token0Amt,
                token1Amt,
                0,
                0,
                address(this),
                now + routerDeadlineDuration
            );
        }

        _farm();

        _convertDustToEarned();        

    }

    function distributeFees(uint256 _earnedAmt) internal returns (uint256) {
        if (_earnedAmt > 0) {
            // Performance fee
            if (controllerFee > 0) {
                uint256 fee = _earnedAmt.mul(controllerFee).div(controllerFeeMax);
                IERC20(earnedAddress).safeTransfer(devAddress, fee);
                _earnedAmt = _earnedAmt.sub(fee);
            }
        }
        return _earnedAmt;
    }

    function distributeReserves(uint256 _earnedAmt) internal returns (uint256) {
        if (_earnedAmt > 0) {
            // Reserves fee
            if (reservesFee > 0) {
                uint256 fee = _earnedAmt.mul(reservesFee).div(reservesFeeMax);
                IERC20(earnedAddress).safeTransfer(reservesAddress, fee);
                _earnedAmt = _earnedAmt.sub(fee);
            }
        }
        return _earnedAmt;
    }    

    function buyBack(uint256 _earnedAmt) internal returns (uint256) {
        uint256 buyBackAmt = _earnedAmt.mul(buyBackRate).div(buyBackRateMax);

        if (uniRouterAddress != buybackRouterAddress) {
            // Example case: LP token on ApeSwap and NATIVE token on PancakeSwap
            
            if (earnedAddress != wbnbAddress) {
                // First convert earn to wbnb
                IERC20(earnedAddress).safeIncreaseAllowance(
                    uniRouterAddress,
                    buyBackAmt
                );

                IXRouter02(uniRouterAddress)
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    buyBackAmt,
                    0,
                    earnedToWBNBPath,
                    address(this),
                    now + routerDeadlineDuration
                );
            }

            // convert all wbnb to Native and burn them
            uint256 wbnbAmt = IERC20(wbnbAddress).balanceOf(address(this));
            if (wbnbAmt > 0) {
                IERC20(wbnbAddress).safeIncreaseAllowance(
                    buybackRouterAddress,
                    wbnbAmt
                );

                IXRouter02(buybackRouterAddress)
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    wbnbAmt,
                    0,
                    WBNBToNATIVEPath,
                    buyBackAddress,
                    now + routerDeadlineDuration
                );
            }            

        } else {
            // Both LP and NATIVE token on same swap

            IERC20(earnedAddress).safeIncreaseAllowance(
                uniRouterAddress,
                buyBackAmt
            );

            IXRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                buyBackAmt,
                0,
                earnedToNATIVEPath,
                buyBackAddress,
                now + routerDeadlineDuration
            );
        }

        return _earnedAmt.sub(buyBackAmt);
    }

    function convertDustToEarned() public nonReentrant {
        require(isAutoComp, "!isAutoComp");
        require(!isSingleVault, "isSingleVault");
        _convertDustToEarned();
    }

    function _convertDustToEarned() internal {
        
        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        // Converts token0 dust (if any) to earned tokens
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Address != earnedAddress && token0Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );

            // Swap all dust tokens to earned tokens
            IXRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                token0Amt,
                0,
                token0ToEarnedPath,
                address(this),
                now + routerDeadlineDuration
            );
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Address != earnedAddress && token1Amt > 0) {
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );

            // Swap all dust tokens to earned tokens
            IXRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                token1Amt,
                0,
                token1ToEarnedPath,
                address(this),
                now + routerDeadlineDuration
            );
        }
    } 

}