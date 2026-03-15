// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * SimpleCounter - A minimal contract for Remix deployment & interaction demo.
 * Deploy with Remix, then use the orange (write) and blue (read) buttons to interact.
 */
contract SimpleCounter {
    uint256 public count;
    string public greeting;

    event CountUpdated(uint256 newCount);
    event GreetingSet(string newGreeting);

    constructor() {
        count = 0;
        greeting = "Hello, Remix!";
    }

    function increment() public {
        count += 1;
        emit CountUpdated(count);
    }

    function decrement() public {
        require(count > 0, "Count cannot go below zero");
        count -= 1;
        emit CountUpdated(count);
    }

    function setGreeting(string memory _greeting) public {
        greeting = _greeting;
        emit GreetingSet(_greeting);
    }

    function getCount() public view returns (uint256) {
        return count;
    }
}
