// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ERC20Token
 * @dev A standard ERC-20 token implementation with minting and burning capabilities
 * 
 * Features:
 * - Standard ERC-20 functionality (transfer, approve, transferFrom)
 * - Minting capability (owner can create new tokens)
 * - Burning capability (users can destroy their tokens)
 * - Configurable initial supply, name, symbol, and decimals
 * 
 * Deploy with Remix:
 * 1. Compile the contract
 * 2. Deploy with constructor parameters:
 *    - _name: Token name (e.g., "My Token")
 *    - _symbol: Token symbol (e.g., "MTK")
 *    - _decimals: Number of decimals (typically 18)
 *    - _initialSupply: Initial token supply (in smallest unit, e.g., 1000000 * 10^18)
 * 3. Interact with the contract using Remix's interface
 */
contract ERC20Token {
    // Token metadata
    string public name;
    string public symbol;
    uint8 public decimals;
    
    // Total supply
    uint256 public totalSupply;
    
    // Balances mapping
    mapping(address => uint256) public balanceOf;
    
    // Allowances mapping (owner => spender => amount)
    mapping(address => mapping(address => uint256)) public allowance;
    
    // Owner address
    address public owner;
    
    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed to, uint256 value);
    event Burn(address indexed from, uint256 value);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    /**
     * @dev Constructor
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _decimals Number of decimals (typically 18)
     * @param _initialSupply Initial token supply (in smallest unit)
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        owner = msg.sender;
        
        if (_initialSupply > 0) {
            totalSupply = _initialSupply;
            balanceOf[msg.sender] = _initialSupply;
            emit Transfer(address(0), msg.sender, _initialSupply);
        }
    }
    
    /**
     * @dev Transfer tokens to a specified address
     * @param _to The address to transfer to
     * @param _value The amount to transfer
     * @return success Whether the transfer was successful
     */
    function transfer(address _to, uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value, "Insufficient balance");
        require(_to != address(0), "Cannot transfer to zero address");
        
        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;
        
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    
    /**
     * @dev Approve a spender to transfer tokens on behalf of the owner
     * @param _spender The address authorized to spend
     * @param _value The maximum amount the spender can transfer
     * @return success Whether the approval was successful
     */
    function approve(address _spender, uint256 _value) public returns (bool success) {
        require(_spender != address(0), "Cannot approve zero address");
        
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }
    
    /**
     * @dev Transfer tokens from one address to another using allowance
     * @param _from The address to transfer from
     * @param _to The address to transfer to
     * @param _value The amount to transfer
     * @return success Whether the transfer was successful
     */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(balanceOf[_from] >= _value, "Insufficient balance");
        require(allowance[_from][msg.sender] >= _value, "Insufficient allowance");
        require(_to != address(0), "Cannot transfer to zero address");
        
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        allowance[_from][msg.sender] -= _value;
        
        emit Transfer(_from, _to, _value);
        return true;
    }
    
    /**
     * @dev Mint new tokens (only owner)
     * @param _to The address to mint tokens to
     * @param _value The amount of tokens to mint
     */
    function mint(address _to, uint256 _value) public onlyOwner {
        require(_to != address(0), "Cannot mint to zero address");
        
        totalSupply += _value;
        balanceOf[_to] += _value;
        
        emit Mint(_to, _value);
        emit Transfer(address(0), _to, _value);
    }
    
    /**
     * @dev Burn tokens from the caller's balance
     * @param _value The amount of tokens to burn
     */
    function burn(uint256 _value) public {
        require(balanceOf[msg.sender] >= _value, "Insufficient balance to burn");
        
        balanceOf[msg.sender] -= _value;
        totalSupply -= _value;
        
        emit Burn(msg.sender, _value);
        emit Transfer(msg.sender, address(0), _value);
    }
    
    /**
     * @dev Get the balance of an address
     * @param _owner The address to query
     * @return balance The balance of the address
     */
    function getBalance(address _owner) public view returns (uint256 balance) {
        return balanceOf[_owner];
    }
    
    /**
     * @dev Get the allowance of a spender for an owner
     * @param _owner The address that owns the tokens
     * @param _spender The address authorized to spend
     * @return remaining The remaining allowance
     */
    function getAllowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowance[_owner][_spender];
    }
}
