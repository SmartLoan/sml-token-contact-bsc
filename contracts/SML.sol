// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.0/contracts/token/ERC20/ERC20.sol";

/**
 * @title SmartLoanToke
 * @author Asvoria Kuan<asvoria@live.com>
 * @dev Use solidity compiler version 0.8.1
 */

contract SML is ERC20 {
    
    enum stages {
        STAGE_INIT,
        STAGE_FUNDING,
        STAGE_GRACE,
        STAGE_REPAYMENT,
        STAGE_END
    }
    // This is the current stage.
    stages public CURENT_STAGE = stages.STAGE_INIT;
    
    int[] public interest_rates = [-20,-10,0,10,20];
    
    string public token_name = "SmartLoanToken";    //Generated
    string public token_symbol = "SML";            //Generated
    
    uint256 public token_borrow = 1000;                   //User key in data, this will be multiplied
    uint256 public loan_duration = 1095 days;           //User key in data, 3 years
    uint256 public loan_payment_duration = 3650 days;   //User key in data, 10 years
    uint public loan_payment_count = loan_payment_duration / 30;
    uint public loan_payment_count_num;
    uint256 public tokenBuyRate = 1;
    //1 ether = 1,000,000,000,000,000,000 wei (10^18)
    
    uint256 public tokenPrice = 0.000001 ether;     //Fix 
    uint256 public initial_token_supply = 1e18;      //Fix
    uint256 public INITIAL_SUPPLY = initial_token_supply * token_borrow;
    address payable public borrower;
    address payable public ownerAdds;                //User key in data
    address payable public tokenWallet;             //Generated
    
    
    uint256 public ICOStartTime = block.timestamp;
    uint256 public ICOEndTime = block.timestamp + loan_duration;
    bool public ICOCompleted;
    
    uint256 public RepaymentStartTime;
    uint256 public monthlySalary = 0;

    address[] public lenders;
    address[] public borrowers;
    uint256[] public payment_principal;
    address payable public deployWallet;
    
    // modifier
    modifier atStage(stages _stage) {
        require(
            CURENT_STAGE == _stage,
            "Function cannot be called at this time."
        );
        _;
    }
    
    modifier whenIcoCompleted{
        require(ICOCompleted);
        _;
    }
    
    modifier onlyCrowdsale{
        require(block.timestamp < ICOEndTime && block.timestamp > ICOStartTime);
        _;
    }

    modifier onlyOwner{
        require(msg.sender == ownerAdds);
        _;
    }

    modifier afterCrowdsale{
        require(block.timestamp > ICOEndTime);
        _;
    }
    
    modifier repaymentPeriod{
        require(block.timestamp > RepaymentStartTime);
        _;
    }
    
    // function
    function nextStage() internal {
        CURENT_STAGE = stages(uint(CURENT_STAGE) + 1);
    }
    
    function destroy() onlyOwner public {
        selfdestruct(ownerAdds);
    }

    function saveAddress() payable public {
        lenders.push(msg.sender);
    }
    function saveAddressBorrower() payable public {
        borrowers.push(msg.sender);
    }
    
    //Call function to start repayment period
    function startRepayment(
            uint256 _monthlySalary
        ) public onlyOwner afterCrowdsale returns(bool){
        RepaymentStartTime = block.timestamp;
        loan_payment_count_num = 0;
        monthlySalary = _monthlySalary * (1 ether); //when input, it is in wei
        _burn(ownerAdds, balanceOf(ownerAdds)); //When start repayment, burn all leftover tokens remained in borrower account
        //calculate payment_principal
        for (uint i=0; i<lenders.length; i++) {
            address payable makePayAdd = payable(address(uint160(lenders[i])));
            payment_principal[i] = balanceOf(makePayAdd)/(loan_payment_count);
        }
        return true;
    }
    
    //Can only start to distribute interest after the repayment period started
    //interests is distributed according to lenders token ownership
    function distributeInterest() public payable onlyOwner afterCrowdsale repaymentPeriod{
        //Interest is 5%per anum of monthly reported salary. monthlySalary
        require(monthlySalary > 0);
        uint256 InterestRate = (monthlySalary/100)* (5)/(INITIAL_SUPPLY);
        uint256 InterestCalc = 0 ether;
        for (uint i=0; i<lenders.length; i++) {
            address payable makePayAdd = payable(address(uint160(lenders[i])));
            InterestCalc = balanceOf(makePayAdd) * (InterestRate);
            require (InterestCalc > 0, "Amount is less than the minimum value");
            require (msg.sender.balance >= InterestCalc, "Contract balance is empty");
            makePayAdd.transfer(InterestCalc); //ether must be in contract balance
        }
    }

    function Repayment() public payable onlyOwner afterCrowdsale repaymentPeriod {
        uint256 tokensRepay;
        uint256 tokensRepayEther = 0 ether;
        
        for (uint i=0; i<lenders.length; i++) {
            address payable makePayAdd = payable(address(uint160(lenders[i])));
            
            tokensRepay = payment_principal[i];
            tokensRepayEther = tokensRepay*(tokenPrice);
            
            require (tokensRepayEther > 0, "Amount is less than the minimum value");
            require (msg.sender.balance >= tokensRepayEther, "Contract balance is empty");
            
            makePayAdd.transfer(tokensRepayEther); //ether must be in contract balance
            transferFrom(makePayAdd,msg.sender,tokensRepay);
            
            _burn(makePayAdd, payment_principal[i]);
        }
        loan_payment_count_num++;
    }
    
    function buyTokens(address debtAdds) public payable onlyCrowdsale{
        address payable token_Wallet = payable(debtAdds);
        require(msg.sender != address(0));
        require(balanceOf(token_Wallet) > 0);
        uint256 etherUsed = uint256(msg.value);
        require(etherUsed > 0);
        uint256 tokensToBuy = etherUsed/(tokenBuyRate);
        
        approve(payable(msg.sender), etherUsed);
        
        // Return extra ether when tokensToBuy > balances[tokenWallet]
        if(tokensToBuy > balanceOf(token_Wallet)){
            uint256 exceedingTokens = tokensToBuy - (balanceOf(token_Wallet));
            uint256 exceedingEther = 0 ether;

            exceedingEther = exceedingTokens * (tokenBuyRate);
            payable(msg.sender).transfer(exceedingEther);
            tokensToBuy = tokensToBuy - (exceedingTokens);
            etherUsed = etherUsed - (exceedingEther);
        }

        transferFrom(token_Wallet,msg.sender,uint256(tokensToBuy));
        payable(token_Wallet).transfer(etherUsed);
        saveAddress();
    }
    
    function depositContract() public payable onlyOwner afterCrowdsale repaymentPeriod{
        require(msg.sender != address(0));
        require(balanceOf(tokenWallet) > 0);
    }

    function emergencyExtract() external payable onlyOwner{
        ownerAdds.transfer(address(this).balance);
    }
    
    function borrowerMint(uint256 tokensBorrowed) public payable {
        borrower = payable(msg.sender);
        tokenWallet = borrower;
        _mint(borrower, (tokensBorrowed));
        saveAddressBorrower();
    }
    
    function checkBorrower() public view returns(bool){
        address checkAdds = msg.sender;

        for (uint i=0; i<borrowers.length; i++) {
            if(checkAdds==borrowers[i]){
                //found match
                return true;
            } 
        }
        return false;
    }

    constructor() ERC20(token_name,token_symbol){
        deployWallet = payable(address(msg.sender));
    }
}
