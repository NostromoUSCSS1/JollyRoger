// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakeFactory.sol";
import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakePair.sol";
import "pancakeswap-peripheral/contracts/interfaces/IPancakeRouter01.sol";
import "pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";


contract JollyRoger is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;
    address[] private _excluded;
    address payable _charityAddress;
    address payable _marketingDevAddress;
   
    uint256 public _tradingStartTime;
    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal = 100000000000 * 10**9;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private constant _name = "Jolly Roger";
    string private constant _symbol = "JOLLY";
    uint8 private constant _decimals = 9;
    
    uint256 private _taxFee = 3;
    uint256 private _previousTaxFee = _taxFee;
    
    uint256 private _liquidityFee = 2;
    uint256 private _previousLiquidityFee = _liquidityFee;

    uint256 private _charityFee = 3;
    uint256 private _previousCharityFee = _charityFee;
    
    uint256 private _marketingAndDevBudget = 1;
    uint256 private _previousMarketingAndDevBudget = _marketingAndDevBudget;

    IPancakeRouter02 public pancakeRouter;
    address public pancakePair;
    
    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = false;
                                    
    uint256 private _maxTxAmount = 1000000000 * 10**9;
    uint256 private constant numTokensSellToAddToLiquidity = 100000000 * 10**9;
    
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);
    event RouterUpdated(address indexed owner, address indexed router, address indexed pair);
    event SwapAndCharity(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoCharity);

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    
    constructor (address router, address payable charityAddress, address payable marketingDevAddress) {
        _rOwned[_msgSender()] = _rTotal;
        
        IPancakeRouter02 _pancakeRouter = IPancakeRouter02(router);
        pancakePair = IPancakeFactory(_pancakeRouter.factory())
            .createPair(address(this), _pancakeRouter.WETH());

        pancakeRouter = _pancakeRouter;
        
        _charityAddress = charityAddress;
        _marketingDevAddress = marketingDevAddress;

        _isExcludedFromFee[_msgSender()] = true;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal - tokenFromReflection(_rOwned[0x000000000000000000000000000000000000dEaD]);
    }

    function LPBurnt() view external returns (uint256) {
        return IPancakePair(pancakePair).balanceOf(0x000000000000000000000000000000000000dEaD);
    }

    function tokensBurnt() view external returns (uint256) {
        return tokenFromReflection(_rOwned[0x000000000000000000000000000000000000dEaD]);
    }

    function showCharityaddress() public view returns(address payable) {
        return _charityAddress;
    }
    
    function showMarketingaddress() public view returns(address payable) {
        return _marketingDevAddress;
    }

    function minimumTokensBeforeSwapAmount() public pure returns (uint256) {
        return numTokensSellToAddToLiquidity;
    }

    function _currentTXAmount() public view returns (uint256) {
        return _maxTX();
    }

    function _maxTX() private view returns (uint256) {
        uint256 time_deployment = block.timestamp - _tradingStartTime;
        if (time_deployment < 1 days) {
            return _maxTxAmount;
        } else if (time_deployment < 2 days) {
            return _maxTxAmount.mul(2);
        } else if (time_deployment < 3 days) {
            return _maxTxAmount.mul(3);
        } else if (time_deployment < 4 days) {
            return _maxTxAmount.mul(4);
        } else if (time_deployment < 5 days) {
            return _maxTxAmount.mul(8);
        } else {
            return _maxTxAmount.mul(10);
        }
    }

    function _currentTaxFee() public view returns (uint256) {
        uint256 multiplier = _dynamicFees();
        return _taxFee.mul(multiplier);
    }

    function _currentLiquidityFee() public view returns (uint256) {
        uint256 multiplier = _dynamicFees();
        return _liquidityFee.mul(multiplier);
    }

    function _currentCharityFee() public view returns (uint256) {
        uint256 multiplier = _dynamicFees();
        return _charityFee.mul(multiplier);
    }

    function _currentMarketingFee() public view returns (uint256) {
        uint256 multiplier = _dynamicFees();
        return _marketingAndDevBudget.mul(multiplier);
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "BEP20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "BEP20: decreased allowance below zero"));
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(!_isExcluded[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,,) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,,) = _getValues(tAmount);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,,) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    function excludeFromReward(address account) public onlyOwner() {
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }
    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);        
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }
    
    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function setSwapAndLiquifyEnabled(bool _swapAndLiquifyEnabled) external onlyOwner() {
        require(swapAndLiquifyEnabled == false); // Can only be turned on once
        swapAndLiquifyEnabled = _swapAndLiquifyEnabled;
        _tradingStartTime = block.timestamp;
        emit SwapAndLiquifyEnabledUpdated(_swapAndLiquifyEnabled);
    }

    function setTaxFeePercent(uint256 taxFee) external onlyOwner() {
        require(taxFee > 0 && taxFee <= 20, "Tax Fee must range from 1 to 20");
        _taxFee = taxFee;
    }
    
    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner() {
        require(liquidityFee > 0 && liquidityFee <= 20, "Liquidity Fee must range from 1 to 20");
        _liquidityFee = liquidityFee;
    }

    function setCharityFeePercent(uint256 charityFee) external onlyOwner() {
        require(charityFee > 0 && charityFee <= 20, "Charity Fee must range from 1 to 20");
        _charityFee = charityFee;
    }

    function setMarketingDevFeePercent(uint256 marketingAndDevBudget) external onlyOwner {
        require(marketingAndDevBudget > 0 && marketingAndDevBudget <= 10, "Charity Fee must range from 1 to 10");
        _marketingAndDevBudget = marketingAndDevBudget; 
    }
   
    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner() {
        require(maxTxPercent !=0,  "Max TX Percentage can't be zero");
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(10**2);
    }
    
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, _getRate());
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity);
    }

    function _dynamicFees() private view returns (uint256) {
        uint256 time_deployment = block.timestamp - _tradingStartTime;
        if (time_deployment < 30 minutes) {
            return (4);
        } else if (time_deployment < 2 hours) {
            return (3);
        } else if (time_deployment < 4 hours) {
            return (2);
        } else {
            return (1);
        }
    }

    function _getTValues(uint256 tAmount) private view returns (uint256, uint256, uint256) {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tLiquidity = calculateLiquidityPlusCharityFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity);
        return (tTransferAmount, tFee, tLiquidity);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tLiquidity, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
    
    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate =  _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }
    
    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        uint256 multiplier = _dynamicFees();
        return _amount.mul(_taxFee).mul(multiplier).div(10**2);
    }

    function calculateLiquidityPlusCharityFee(uint256 _amount) private view returns (uint256) {
        uint256 multiplier = _dynamicFees();
        return _amount.mul(_liquidityFee + _charityFee + _marketingAndDevBudget).mul(multiplier).div(10**2);
    }

    function removeAllFee() private {
        if(_taxFee == 0 && _liquidityFee == 0 && _marketingAndDevBudget == 0 && _charityFee == 0) return;
        
        _previousTaxFee = _taxFee;
        _previousLiquidityFee = _liquidityFee;
        _previousCharityFee = _charityFee;
        _previousMarketingAndDevBudget = _marketingAndDevBudget;
        
        _taxFee = 0;
        _liquidityFee = 0;
        _charityFee = 0;
        _marketingAndDevBudget = 0;
    }

    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
        _liquidityFee = _previousLiquidityFee;
        _charityFee = _previousCharityFee;
        _marketingAndDevBudget = _previousMarketingAndDevBudget;
    }
    
    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "BEP20: transfer from or to the zero address");
        require(to != address(0), "BEP20: transfer from or to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if(from != owner() && to != owner()) {
            require(amount <= _maxTX(), "Transfer amount cannot exceeds MaxTXAmount");
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        
        if(contractTokenBalance >= _maxTX())
        {
            contractTokenBalance = _maxTX();
        }
        
        bool overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != pancakePair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = numTokensSellToAddToLiquidity;
            swapAndLiquify(contractTokenBalance);
        }
        
        bool takeFee = true;
        
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }
        
        _tokenTransfer(from,to,amount,takeFee);
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);
        uint256 totalLiqFee = _marketingAndDevBudget + _liquidityFee + _charityFee;

        uint256 initialBalance = address(this).balance;

        swapTokensForBNB(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        uint256 charityBalance = newBalance.div(totalLiqFee).mul(_charityFee);
        uint256 charityPortion = otherHalf.div(totalLiqFee).mul(_charityFee);

        uint256 marketingBalance = newBalance.div(totalLiqFee).mul(_marketingAndDevBudget);
        uint256 marketingPortion = otherHalf.div(totalLiqFee).mul(_marketingAndDevBudget);
        
        uint256 finalBalance = newBalance.sub(charityBalance).sub(marketingBalance);
        uint256 finalHalf = otherHalf.sub(charityPortion).sub(marketingPortion);

        (bool sent, bytes memory data) = _charityAddress.call{value: charityBalance}("");
        if(sent){
            _tokenTransfer(address(this), 0x000000000000000000000000000000000000dEaD, charityPortion, false);
            emit Transfer(address(this), 0x000000000000000000000000000000000000dEaD, charityPortion);
        } else {
            addLiquidity(charityPortion, charityBalance, _charityAddress);
        }
        
        (sent, data) = _marketingDevAddress.call{value: marketingBalance}("");
        if(sent){
            _tokenTransfer(address(this), 0x000000000000000000000000000000000000dEaD, marketingPortion, false);
            emit Transfer(address(this), 0x000000000000000000000000000000000000dEaD, marketingPortion);
        } else {
            addLiquidity(marketingPortion, marketingBalance, _marketingDevAddress);
        }

        addLiquidity(finalHalf, finalBalance, address(0x000000000000000000000000000000000000dEaD));
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForBNB(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeRouter.WETH();

        _approve(address(this), address(pancakeRouter), tokenAmount);

        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount, address charity) private {
        _approve(address(this), address(pancakeRouter), tokenAmount);

        pancakeRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            charity,
            block.timestamp
        );
    }

    function _tokenTransfer(address sender, address recipient, uint256 amount,bool takeFee) private {
        if(!takeFee)
            removeAllFee();
        
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
        
        if(!takeFee)
            restoreAllFee();
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);           
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);   
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function setNewRouterAddress(address _newRouterAddress) external onlyOwner {
        require(_newRouterAddress != address(0), "Router can not be the zero address");
        require(_newRouterAddress != address(pancakeRouter), "This is the current router");

        IPancakeRouter02 _pancakeRouter = IPancakeRouter02(_newRouterAddress);
        pancakeRouter = _pancakeRouter;

        pancakePair = IPancakeFactory(_pancakeRouter.factory())
        .getPair(address(this), _pancakeRouter.WETH());

        // If the pair doesn't exist on the new dex, create it.
        if(pancakePair == address(0))
        {
            // create the new pair for the new router
            pancakePair = IPancakeFactory(_pancakeRouter.factory())
            .createPair(address(this), _pancakeRouter.WETH());
        }

        emit RouterUpdated(msg.sender, address(pancakeRouter), pancakePair);
    }

    event SafeTransferedBNB(address to, uint value);

    function safeTransferBNB(address to, uint value) public onlyOwner {	
        (bool success,) = to.call{value:value}(new bytes(0));	
        require(success, 'TransferHelper: BNB_TRANSFER_FAILED');
        emit SafeTransferedBNB(to, value);	
    }

    event SafeTransferDone(address token, address to, uint value);
    
    function safeTransfer(address token, address to, uint value) public onlyOwner {	
        require(token != address(this));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));	
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
        emit SafeTransferDone(token, to, value);	
    }
}