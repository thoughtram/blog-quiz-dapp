pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./Quiz.sol";

contract MockTimeMachine is TimeSource{

  uint private _mocked_now;

  constructor(uint mocked) public payable {
    _mocked_now = mocked;
  }

  function get_now() public override returns (uint) {
    return _mocked_now;
  }

  function set_now(uint mocked_now) public returns (uint) {
    return _mocked_now = mocked_now;
  }
}

contract QuizTest is DSTest {
    Quiz egg;
    MockTimeMachine _time_machine;

    string SALT = "o";
    bytes32 WINNING_HASH = 0xf539ba76cb28bd8b154e5e1e046c11cc09c5a4831299ea08e5a04ce250df879f;

    function setUp() public {
        _time_machine = new MockTimeMachine(1000);
        egg = (new Quiz){value: 1 ether}(_time_machine, 2000, 3000, WINNING_HASH);
    }

    function test_initial_state() public {
        assertEq(address(egg).balance, 1 ether);
        assertTrue(egg.get_state() == GameState.Started);
    }

    function test_reveal_before_reveal_epoch_started() public {
        assertTrue(egg.get_state() == GameState.Started);

        try egg.reveal_answer(SALT) {
            fail();
        } catch Error(string memory reason) {
            assertEq(reason, "Can not reveal before reveal_epoch started");
            assertTrue(egg.get_state() == GameState.Started);
        }
    }

    function test_reveal_after_scam_epoch_started() public {
        assertTrue(egg.get_state() == GameState.Started);
        _time_machine.set_now(3000);
        try egg.reveal_answer(SALT) {
            fail();
        } catch Error(string memory reason) {
            assertEq(reason, "Too late scammer!");
        }
    }

    function test_reveal_after_reveal_epoch_started() public {
        assertTrue(egg.get_state() == GameState.Started);
        _time_machine.set_now(2000);
        egg.reveal_answer(SALT);
        assertTrue(egg.get_state() == GameState.Revealed);
    }

    function test_reveal_when_already_revealed() public {
        test_reveal_after_reveal_epoch_started();
        try egg.reveal_answer(SALT) {
            fail();
        } catch Error(string memory reason) {
            assertEq(reason, "Already revealed. Can not reveal again!");
        }
    }

    function test_claim_while_game_is_on() public {
        egg.make_guess("foo");
        try egg.claim_win() {
            fail();
        } catch Error(string memory reason) {
            assertEq(reason, "Be patient! The game is still running.");
        }
    }

    function test_claim_win_after_revealed() public {
        uint256 old_balance = address(this).balance;
        egg.make_guess("foo");
        _time_machine.set_now(2000);
        egg.reveal_answer(SALT);
        egg.claim_win();
        assertTrue(address(this).balance > old_balance);
    }

    // function test_guess() public {
    //     egg.make_guess("foo");
    //     egg.claim_win();
    // }

    receive() external payable { }

}
