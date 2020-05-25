pragma solidity ^0.5.15;

import "ds-test/test.sol";

import "./FooFoo.sol";

contract FooFooTest is DSTest {
    FooFoo foo;

    function setUp() public {
        foo = new FooFoo();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
