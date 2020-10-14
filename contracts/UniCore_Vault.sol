// SPDX-License-Identifier: WHO GIVES A FUCK ANYWAY??

pragma solidity >= 0.6.0;

import "./UniCore_Libraries.sol";
import "./UniCore_Interfaces.sol";


// Vault distributes fees equally amongst staked pools

contract UniCore_Vault {
    using SafeMath for uint256;


    address public UniCore; //token address
    
    address public Treasury1;
    address public Treasury2;
    address public Treasury3;
    uint256 treasuryFee;
    uint256 pendingTreasuryRewards;
    

//USERS METRICS
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardPaid; // Already Paid. See explanation below.
        //  pending reward = (user.amount * pool.UniCorePerShare) - user.rewardPaid
    }
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    
//POOL METRICS
    struct PoolInfo {
        address token;                // Address of staked token contract.
        uint256 allocPoint;           // How many allocation points assigned to this pool. UniCores to distribute per block. (ETH = 2.3M blocks per year)
        uint256 accUniCorePerShare;   // Accumulated UniCores per share, times 1e18. See below.
        bool withdrawable;            // Is this pool withdrawable or not
        
        mapping(address => mapping(address => uint256)) allowance;
    }
    PoolInfo[] public poolInfo;

    uint256 public totalAllocPoint;     // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public pendingRewards;      // pending rewards awaiting anyone to massUpdate
    uint256 public contractStartBlock;
    uint256 public epochCalculationStartBlock;
    uint256 public cumulativeRewardsSinceStart;
    uint256 public rewardsInThisEpoch;
    uint public epoch;

//EVENTS
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 _pid, uint256 value);

    
//INITIALIZE 
    constructor() public {

        UniCore = address(0xBC935114084188636d7C854f49f03F0A85B8FDF1);
        Treasury1 = address(0xF4D7a0E8a68345442172F45cAbD272c25320AA96); //TESTNET
        
        Treasury2 = address(0x397f9694Ca604c2bbdfB5c86227A64853940FB49); //stpd 
        Treasury3 = address(0x397f9694Ca604c2bbdfB5c86227A64853940FB49); //QS 
        treasuryFee = 500; //5%
        
        contractStartBlock = block.number;
    }
    
//==================================================================================================================================
//POOL
    
 //view stuff
 
    function poolLength() external view returns (uint256) {
        return poolInfo.length; //number of pools (per pid)
    }
    
    // Returns fees generated since start of this contract
    function averageFeesPerBlockSinceStart() external view returns (uint averagePerBlock) {
        averagePerBlock = cumulativeRewardsSinceStart.add(rewardsInThisEpoch).div(block.number.sub(contractStartBlock));
    }

    // Returns averge fees in this epoch
    function averageFeesPerBlockEpoch() external view returns (uint256 averagePerBlock) {
        averagePerBlock = rewardsInThisEpoch.div(block.number.sub(epochCalculationStartBlock));
    }

    // For easy graphing historical epoch rewards
    mapping(uint => uint256) public epochRewards;

 //set stuff (govenrors)

    // Add a new token pool. Can only be called by governors.
    function addPool( uint256 _allocPoint, address _token, bool _withUpdate, bool _withdrawable) public governanceLevel(2) {
        if (_withUpdate) { massUpdatePools();}

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token,"Error pool already added");
        }

        totalAllocPoint = totalAllocPoint.add(_allocPoint); //pre-allocation

        poolInfo.push(
            PoolInfo({
                token: _token,
                allocPoint: _allocPoint,
                accUniCorePerShare: 0,
                withdrawable : _withdrawable
            })
        );
    }

    // Updates the given pool's  allocation points. Can only be called with right governance levels.
    function setPool(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public governanceLevel(2) {
        if (_withUpdate) {massUpdatePools();}

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update the given pool's ability to withdraw tokens
    function setPoolWithdrawable(uint256 _pid, bool _withdrawable) public governanceLevel(2) {
        poolInfo[_pid].withdrawable = _withdrawable;
    }
    
 //set stuff (anybody)
  
    //Starts a new calculation epoch; Because average since start will not be accurate
    function startNewEpoch() public {
        require(epochCalculationStartBlock + 50000 < block.number, "New epoch not ready yet"); // 50k blocks = About a week
        epochRewards[epoch] = rewardsInThisEpoch;
        cumulativeRewardsSinceStart = cumulativeRewardsSinceStart.add(rewardsInThisEpoch);
        rewardsInThisEpoch = 0;
        epochCalculationStartBlock = block.number;
        ++epoch;
    }
    
    // Updates the reward variables of the given pool
    function updatePool(uint256 _pid) internal returns (uint256 UniCoreRewardWhole) {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 tokenSupply = IERC20(pool.token).balanceOf(address(this));
        if (tokenSupply == 0) { // avoids division by 0 errors
            return 0;
        }
        UniCoreRewardWhole = pendingRewards     // Multiplies pending rewards by allocation point of this pool and then total allocation
            .mul(pool.allocPoint)               // getting the percent of total pending rewards this pool should get
            .div(totalAllocPoint);              // we can do this because pools are only mass updated
        
        uint256 UniCoreRewardFee = UniCoreRewardWhole.mul(treasuryFee).div(10000);
        uint256 UniCoreRewardToDistribute = UniCoreRewardWhole.sub(UniCoreRewardFee);

        pendingTreasuryRewards = pendingTreasuryRewards.add(UniCoreRewardFee);

        pool.accUniCorePerShare = pool.accUniCorePerShare.add(UniCoreRewardToDistribute.mul(1e18).div(tokenSupply));
    }
    function massUpdatePools() public {
        uint256 length = poolInfo.length; 
        uint allRewards;
        
        for (uint256 pid = 0; pid < length; ++pid) {
            allRewards = allRewards.add(updatePool(pid)); //calls updatePool(pid)
        }
        pendingRewards = pendingRewards.sub(allRewards);
    }
    
    //payout of UniCore Rewards, uses SafeUnicoreTransfer
    function updateAndPayOutPending(uint256 _pid, address user) internal {
        
        updatePool(_pid);

        uint256 pending = pendingUniCore(_pid, user);

        safeUniCoreTransfer(user, pending);
    }
    
    
    // Safe UniCore transfer function, Manages rounding errors.
    function safeUniCoreTransfer(address _to, uint256 _amount) internal {   //TODO = pass internal
        if(_amount == 0) return;

        uint256 UniCoreBal = IERC20(UniCore).balanceOf(address(this));
        if (_amount >= UniCoreBal) { IERC20(UniCore).transfer(_to, UniCoreBal);} 
        else { IERC20(UniCore).transfer(_to, _amount);}

        transferTreasuryFees(); //adds unecessary gas for users, team can trigger the function manually
        UniCoreBalance = IERC20(UniCore).balanceOf(address(this));
    }

//external call from token

    /* @dev called by the token after each fee transfer to the vault.
    *       updates the pendingRewards and the rewardsInThisEpoch variables
    */      
    modifier onlyUniCore() {
        require(msg.sender == UniCore);
        _;
    }
    
    uint256 private UniCoreBalance;
    function updateRewards() external onlyUniCore {  //function addPendingRewards(uint256  for CORE
        uint256 newRewards = IERC20(UniCore).balanceOf(address(this)).sub(UniCoreBalance); //delta vs previous balanceOf

        if(newRewards > 0) {
            UniCoreBalance =  IERC20(UniCore).balanceOf(address(this)); //balance snapshot
            pendingRewards = pendingRewards.add(newRewards);
            rewardsInThisEpoch = rewardsInThisEpoch.add(newRewards);
        }
        
    }

//==================================================================================================================================
//USERS

    // Deposit tokens to Vault to get allocation rewards
    function deposit(uint256 _pid, uint256 _amount) external {
        require(_amount > 0, "cannot deposit zero tokens");
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updateAndPayOutPending(_pid, msg.sender); //Transfer pending tokens, updates the pools 

        //Transfer the amounts from user
        IERC20(pool.token).transferFrom(msg.sender, address(this), _amount);
        user.amount = user.amount.add(_amount);

        //Finalize
        user.rewardPaid = user.amount.mul(pool.accUniCorePerShare).div(1e18);
        
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw tokens from Vault.
    function withdraw(uint256 _pid, uint256 _amount) external {
        _withdraw(_pid, _amount, msg.sender, msg.sender);
        transferTreasuryFees(); //incurs a gas penalty -> treasury fees transfer
    }
    function _withdraw(uint256 _pid, uint256 _amount, address from, address to) internal {

        PoolInfo storage pool = poolInfo[_pid];
        require(pool.withdrawable, "Withdrawing from this pool is disabled");
        
        UserInfo storage user = userInfo[_pid][from];
        require(user.amount >= _amount, "withdraw: user amount insufficient");

        updateAndPayOutPending(_pid, from); // //Transfer pending tokens, updates the pools 

        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            IERC20(pool.token).transfer(address(to), _amount);
        }
        user.rewardPaid = user.amount.mul(pool.accUniCorePerShare).div(1e18);

        emit Withdraw(to, _pid, _amount);
    }


    // Getter function to see pending UniCore rewards per user.
    function pendingUniCore(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accUniCorePerShare = pool.accUniCorePerShare;

        return user.amount.mul(accUniCorePerShare).div(1e18).sub(user.rewardPaid);
    }
    

//==================================================================================================================================
//TREASURY 

    function transferTreasuryFees() public {
        if(pendingTreasuryRewards == 0) return;

        uint256 UniCorebal = IERC20(UniCore).balanceOf(address(this));
        
        //splitRewards
        uint256 rewards3 = pendingTreasuryRewards.mul(19).div(100); //stpd
        uint256 rewards2 = pendingTreasuryRewards.mul(19).div(100); //qtsr
        uint256 rewards1 = pendingTreasuryRewards.sub(rewards3).sub(rewards2); //team
        
        
        //manages overflows or bad math
        if (pendingTreasuryRewards > UniCorebal) {
            rewards3 = UniCorebal.mul(19).div(100); //stpd
            rewards2 = UniCorebal.mul(19).div(100); //qtsr
            rewards1 = UniCorebal.sub(rewards3).sub(rewards2); //team
        } 

            IERC20(UniCore).transfer(Treasury3, rewards3);
            IERC20(UniCore).transfer(Treasury2, rewards2);
            IERC20(UniCore).transfer(Treasury1, rewards1);

            UniCoreBalance = IERC20(UniCore).balanceOf(address(this));
        
            pendingTreasuryRewards = 0;
    }


//==================================================================================================================================
//GOVERNANCE & UTILS

//Governance inherited from governance levels of UniCoreVaultAddress
    function viewGovernanceLevel(address _address) public view returns(uint8) {
        return IUniCore(UniCore).viewGovernanceLevel(_address);
    }
    modifier governanceLevel(uint8 _level){
        require(viewGovernanceLevel(msg.sender) >= _level, "Grow some mustache kiddo...");
        _;
    }

// utils    
    function isContract(address addr) public view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
    
    // function that lets owner/governance contract
    // approve allowance for any token inside this contract
    // This means all future UNI like airdrops are covered
    // And at the same time allows us to give allowance to strategy contracts.
    // Upcoming cYFI etc vaults strategy contracts will use this function to manage and farm yield on value locked
    function setContractAllowance(address tokenAddress, uint256 _amount, address contractAddress) public governanceLevel(2) {
        require(isContract(contractAddress), "Recipent is not a smart contract, BOOOOOOO");
        require(block.number > contractStartBlock.add(95000), "Governance setup grace period not over"); // about 2weeks
        IERC20(tokenAddress).approve(contractAddress, _amount);
    }
}
