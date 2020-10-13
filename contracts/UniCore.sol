// SPDX-License-Identifier: WHO GIVES A FUCK ANYWAY??

pragma solidity >= 0.6.6;

import "./UniCore_Libraries.sol";
import "./UniCore_Interfaces.sol";


contract UniCore_Token is Context, IERC20 {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    event LiquidityAddition(address indexed dst, uint value);
    event LPTokenClaimed(address dst, uint value);

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 public constant initialSupply = 1000*1e18; // 1k
    uint256 public contractStartTimestamp;

    address public UniswapPair;
    address public Vault;
    
    IUniswapV2Router02 public uniswapRouterV2;
    IUniswapV2Factory public uniswapFactory;
    
//=========================================================================================================================================

    function initialSetup() internal {
        _name = "UniCore";
        _symbol = "UNICORE";
        _decimals = 18;
        _mint(address(this), initialSupply); //tokens minted to the token contract.
        
        setBuySellFees(5, 11); //0.5% on buy, 1.1% on sell
        contractStartTimestamp = block.timestamp;
        
        POOL_CreateUniswapPair(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        //UniswapV2Router02 = UniswapV2Router02
        //0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f = UniswapV2Factory
    }


//=========================================================================================================================================
    /* Liquidity generation logic
    * Steps - All tokens that will ever exist go to this contract
    *  
    * This contract accepts ETH as payable
    * ETH is mapped to people
    *    
    * When liquidity generation event is over 
    * everyone can call the mint LP function.
    *    
    * which will put all the ETH and tokens inside the uniswap contract
    * without any involvement
    *    
    * This LP will go into this contract
    * And will be able to proportionally be withdrawn based on ETH put in
    *
    * emergency drain function allows the contract owner to drain all ETH and tokens from this contract
    * After the liquidity generation event happened. In case something goes wrong, to send ETH back
    */

    string public liquidityGenerationParticipationAgreement = "I agree that the developers and affiliated parties of the UniCore team are not responsible for your funds";

    function liquidityGenerationOngoing() public view returns (bool) {
        return contractStartTimestamp.add(3 days) > block.timestamp;
    }

    // Emergency drain in case of a bug
    function emergencyDrain24hAfterLiquidityGenerationEventIsDone() public governanceLevel(2) {
        require(contractStartTimestamp.add(4 days) < block.timestamp, "Liquidity generation grace period still ongoing"); // About 24h after liquidity generation happens
        (bool success, ) = msg.sender.call{value:(address(this).balance)}("");
        require(success, "Transfer failed.");
       
        _balances[msg.sender] = _balances[address(this)];
        _balances[address(this)] = 0;
    }

    uint256 public totalLPTokensMinted;
    uint256 public totalETHContributed;
    uint256 public LPperETHUnit;
    bool public LPGenerationCompleted;

    mapping (address => uint)  public ethContributed;

//Pool UniSwap pair creation method (see InitialSetup() )
    function POOL_CreateUniswapPair(address router, address factory) public governanceLevel(2) returns (address) {
        uniswapRouterV2 = IUniswapV2Router02(router != address(0) ? router : 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapFactory = IUniswapV2Factory(factory != address(0) ? factory : 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f); 
        require(UniswapPair == address(0), "Token: pool already created");
        
        UniswapPair = uniswapFactory.createPair(address(uniswapRouterV2.WETH()),address(this));
        
        (UniswapPair); //whitelisting the pair (no fee, no cooldown)
        
        setNoCooldownList(UniswapPair, true);
        return UniswapPair;
    }

//During LP Generation Event: Users deposit funds

    function USER_addLiquidity(bool agreesToTermsOutlinedInLiquidityGenerationParticipationAgreement) public payable {
        require(msg.value <= 25*1e18, "max 25ETH contribution per address");
        require(totalETHContributed+msg.value <= 500*1e18, "500 ETH Hard cap"); 
        
        require(liquidityGenerationOngoing(), "Liquidity Generation Event over");
        require(agreesToTermsOutlinedInLiquidityGenerationParticipationAgreement, "No agreement provided");
        
        ethContributed[msg.sender] = ethContributed[msg.sender].add(msg.value);
        totalETHContributed = totalETHContributed.add(msg.value); // for front end display during LGE
        emit LiquidityAddition(msg.sender, msg.value);
    }

    function USER_RemoveLiquidity() public {
        require(LPGenerationCompleted, "Event not over yet");
        require(ethContributed[msg.sender] > 0 , "Nothing to claim, move along");
        
        IUniswapV2Pair pair = IUniswapV2Pair(UniswapPair);
        uint256 amountLPToTransfer = ethContributed[msg.sender].mul(LPperETHUnit).div(1e18);
        pair.transfer(msg.sender, amountLPToTransfer); // stored as 1e18x value for change
        ethContributed[msg.sender] = 0;
        emit LPTokenClaimed(msg.sender, amountLPToTransfer);
    }

//After LP Generation Event: Pool adds liquidity.

    function POOL_CreateLiquidity() public {
        require(liquidityGenerationOngoing() == false, "Liquidity generation onging");
        require(LPGenerationCompleted == false, "Liquidity generation already finished");
        
        totalETHContributed = address(this).balance;
        IUniswapV2Pair pair = IUniswapV2Pair(UniswapPair);
        
        //Wrap eth
        address WETH = uniswapRouterV2.WETH();
        
        //Send to UniSwap
        IWETH(WETH).deposit{value : totalETHContributed}();
        require(address(this).balance == 0 , "Transfer Failed");
        IWETH(WETH).transfer(address(pair),totalETHContributed);
        
        emit Transfer(address(this), address(pair), _balances[address(this)]);
        
        //UniCore balances transfer
        _balances[address(pair)] = _balances[address(this)];
        _balances[address(this)] = 0;
        pair.mint(address(this));       //mint LP tokens. lock method in UniSwapPairV2 PREVENTS FROM DOING IT TWICE
        
        totalLPTokensMinted = pair.balanceOf(address(this));
        
        require(totalLPTokensMinted != 0 , "LP creation failed");
        LPperETHUnit = totalLPTokensMinted.mul(1e18).div(totalETHContributed); // 1e18x for  change
        require(LPperETHUnit != 0 , "LP creation failed");
        
        sync(); //snapshot of the LPtokens balance
        LPGenerationCompleted = true;
    }


//=========================================================================================================================================
    //overriden _transfer to take Fees
    function _transfer(address sender, address recipient, uint256 amount) internal virtual CoolDown(sender) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
    
        lastTransfer[sender] = block.number; //updates the last transfer of the sender
        sync(); //snapshot  of Uniswap LPtoken totalSupply;
        
        
        //updates _balances
        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");

        //calculate net amounts and fee
        (uint256 toAmount, uint256 toFee) = calculateAmountAndFee(sender, amount);
        
        //Send Reward to Vault 1st
        if(toFee > 0 && Vault != address(0)){
            _balances[Vault] = _balances[Vault].add(toFee);
            IVault(Vault).updateRewards(); //keeping track of fees
            emit Transfer(sender, Vault, toFee);
        }
        //transfer to recipient
        _balances[recipient] = _balances[recipient].add(toAmount);
        emit Transfer(sender, recipient, toAmount);

        //checks if LPWithdrawal happened, throw if inconsistency between the UNIv2 tokens balance.
        blockLPWithdrawal(); 
    }
     
//=========================================================================================================================================
// ERC20 and Overrides

    function name() public view returns (string memory) {
        return _name;
    }
    
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public override view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address _owner) public override view returns (uint256) {
        return _balances[_owner];
    }
    
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public virtual  override view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public virtual override  returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    
    function transferFrom( address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve( sender, _msgSender(),  _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
    
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool){
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }
    
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }
    
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(
            amount,
            "ERC20: burn amount exceeds balance"
        );
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }
    
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual{}



//=========================================================================================================================================
//FEE_APPROVER (now included into the token)

    mapping (address => bool) public noFeeList;
    
    uint256 public lastTotalSupplyOfLPTokens;
    function sync() public {
        lastTotalSupplyOfLPTokens = IERC20(UniswapPair).totalSupply();
    }

    function blockLPWithdrawal() internal view returns(bool) {
        require(lastTotalSupplyOfLPTokens <= IERC20(UniswapPair).totalSupply(), "Liquidity withdrawals forbidden");
        return true;
    }
    
    function calculateAmountAndFee(address sender, uint256 amount) public view returns (uint256 netAmount, uint256 fee){

        if(sender == Vault) { fee = 0;} // Don't have a fee when Vault is sending, or infinite loop
        else if(sender == UniswapPair){ fee = amount.mul(buyFee).div(1000);}
        else { fee = amount.mul(sellFee).div(1000);}
        
        netAmount = amount.sub(fee);
    }

    
//=========================================================================================================================================
//cooldown (prevents frontrunning bots): forces to wait x blocks between transactions
    uint8 public coolDown;                          // ecosysten cooldown: blocks to wait between to transactions
    mapping(address => uint8) private addCoolDown;  // additional cooldown for specific users
    mapping(address => bool) private noCoolDown;    // whitelisted contracts, like UniSwap
    mapping(address => uint256) public lastTransfer; 
 
    modifier CoolDown(address _address) {
        if(noCoolDown[_address] == false ){
            require(block.number >= lastTransfer[_address]+coolDown+addCoolDown[_address]);
        }
        _;
    }
    function viewCoolDown(address _address) public view returns(uint8){
        return coolDown+addCoolDown[_address];
    }
    
//=========================================================================================================================================
//Governance
    /**
     * @dev multi tiered governance logic
     * 
     * 0: plebs
     * 1: voting contracts (setup later in DAO)
     * 2: governors
     * 
    */
    mapping(address => uint8) public governanceLevels;
    
    modifier governanceLevel(uint8 _level){
        require(governanceLevels[msg.sender] >= _level, "Grow some mustache kiddo...");
        _;
    }
    function setGovernanceLevel(address _address, uint8 _level) public governanceLevel(_level) {
        governanceLevels[_address] = _level;
    }
    
    function viewGovernanceLevel(address _address) public view returns(uint8) {
        return governanceLevels[_address];
    }

//== Governable Functions
    
    //External variables
        function setUniswapPair(address _UniswapPair) public governanceLevel(2) {
            UniswapPair = _UniswapPair;
        }
        
        function setVault(address _Vault) public governanceLevel(2) {
            Vault = _Vault;
        }
        
        //Mints tokens to a specified address
        function mintTo(address account, uint256 amount) public governanceLevel(1) {
            _mint(account, amount);
        }
       
        //burns tokens from the contract (holding them)
        function burnToken(uint256 amount) public governanceLevel(1) {
            _burn(address(this), amount);
        }
        
        
    //CoolDown
        function setNoCooldownList(address _address, bool _bool) public governanceLevel(1) {
            noCoolDown[_address] = _bool;
        }
        
        //Changes basic block cooldown a all users
        function changeEcosystemCooldown(uint8 _coolDown) public governanceLevel(1) {
            coolDown = _coolDown;
        }
        
        //Adds additional cooldown a specific address (frontrunning bots mitigation
        function addAccountCooldown(address account, uint8 _coolDown) public governanceLevel(1) {
            addCoolDown[account] = _coolDown;
        }
    
    
    //Fees
        uint256 public buyFee; uint256 public sellFee;
        function setBuySellFees(uint256 _buyFee, uint256 _sellFee) public governanceLevel(1) {
            buyFee = _buyFee;  //base 1000 -> 1 = 0.1%
            sellFee = _sellFee;
        }
        
        function setNoFeeList(address _address, bool _bool) public governanceLevel(1) {
          noFeeList[_address] =  _bool;
        }
    
    //Treasury management 
        address public Treasury1; //mktg
        address public Treasury2; //stpd
        address public Treasury3; //qtsr
        
        function setTreasury1(address _treasury) public governanceLevel(2) {
            Treasury1 = _treasury;
        }
        function setTreasury2(address _treasury) public {
            require(msg.sender == Treasury2);
            Treasury2 = _treasury;
        }
        function setTreasury3(address _treasury) public  {
            require(msg.sender == Treasury3);
            Treasury3 = _treasury;
        }
        


}

