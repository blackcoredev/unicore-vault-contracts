// SPDX-License-Identifier: WHO GIVES A FUCK ANYWAY??


/* UNICORE is a set of 4 contracts
* Unicore Token (used for LGE)
* Uniswap Pair (when you trade it, and add liquidity)
* wrapper: converting your liquidity to wrapped LP
* vault: where you stake (deposit) the wrapped liquidity
*
* before every interface (contract) you see an address // 0x...
* use this 0x to "deplpy at" in remix (see tutorial)
* you should have 4 contracts you can interact with.
* more instructions are in the interface details. 
*/

   
pragma solidity ^0.6.6;


// 
interface IUniCore{
    
    /* USER_functions(): once tokens is launched,
    * users can send ETH to the contrat (red button).
    * users can also remove their ETH before LGE if they change their mind.
    *
    * bool = true
    * (it's the acceptance of the disclaimer)
    *
    * IMPORTANT: you need to add ETH in the transaction to pledgeLiquidity.
    * Before you click on the red button, go to the top of the buttons menu
    * (where you see the Environement and your account)
    * and under VALUE, put 0.1 and replace wei by Ether.
    * !!! once done, pub back ZERO (Remix does not reset it)
    *
    */
    function USER_PledgeLiquidity(bool agreesToTermsOutlinedInLiquidityGenerationParticipationAgreement) external payable;
    function USER_UNPledgeLiquidity() external;
    
    /* POOL_functions(): Anybody can CreateLiquidity 
    * once the cutoff date is passed
    * approve the wrapper to take your UNIv2.
    *
    * Once liquidity is created, you can claim 
    * your wrapped tokens:
    * -> see UNIv2 staying on the token
    * -> see wUNIv2 sent to your address
    */
    function POOL_CreateLiquidity() external;
    
    function USER_ClaimWrappedLiquidity() external;
}



//
interface IUniswapPair {
    
    /* approve(): Before you can WRAP tokens (if you decide too), you need to 
    * approve the wrapper to take your UNIv2.
    *
    * spender = 0x8E9174C86A25CA2d46DB4478cFFd12adb4041C83
    * amount = 99999999999999999999999999999999999
    */
    function approve(address spender, uint256 amount) external; 
}



// 
interface IWrapper{
    
    // use this function to wrap any UNIv2 token and get the wrapped token
    function wrapUNIv2(uint256 amount) external;


    /* approve(): Once you get WRAP tokens (from LGE or manual wrapping)
    * you need to approve the VAULT to take them so you can deposit
    *
    * spender = 0xfa2A3eB3218BCD06B87b964dF7765cA16E712589
    * amount = 99999999999999999999999999999999999
    */
    function approve(address spender, uint256 amount) external; 
}



// 
interface IVault{
    
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    
    // massUpdate() does of refresh of the pool metrics and updates pendingUnicore
    function massUpdatePools() external;
    
    
    /* pendingUnicore() let's you see your pending Unicores 
    * (assuming massupdate has run since rewards were collected)
    *
    * _pid = 0 
    * _user = your ethereum address
    *
    */
    function pendingUniCore(uint256 _pid, address _user) external view returns (uint256) ;
    
}
