pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./Quiz.sol";

contract MockTimeMachine is ITimeSource{

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

contract MockSender is ISenderSource{

  address payable public mock_sender;

  function set_sender(address payable sender) public {
      mock_sender = sender;
  }

  function get_sender(address payable who) public override returns (address payable) {
    return mock_sender;
  }
}

contract QuizTest is DSTest {
    Quiz egg;
    MockTimeMachine _time_machine;
    MockSender _sender_source;

    string SALT = "o";
    bytes32 WINNING_HASH = 0xf539ba76cb28bd8b154e5e1e046c11cc09c5a4831299ea08e5a04ce250df879f;

    address payable ALICE = 0xcda949D0415aF93828f91E1b6B130F8eB407D704;
    address payable BOB = 0xcca949D0415aF93828F91E1B6b130f8eB407d704;
    address payable LAHJA = 0xCCa849D0415Af93828F91e1B6b130f8Eb407D704;

    function setUp() public {
        _time_machine = new MockTimeMachine(1000);
        _sender_source = new MockSender();
        _sender_source.set_sender(ALICE);
        egg = (new Quiz){value: 5 ether}(_time_machine, _sender_source, 2000, 3000, WINNING_HASH);
    }

    function test_initial_state() public {
        assertEq(address(egg).balance, 5 ether);
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
        assertEq(ALICE.balance, 0 ether);
        egg.make_guess("foo");
        _time_machine.set_now(2000);
        egg.reveal_answer(SALT);
        egg.claim_win();
        assertEq(ALICE.balance, 5 ether);
    }

    function test_two_winner_claim_reward() public {
        // Alice (default) makes a guess
        assertEq(ALICE.balance, 0 ether);
        egg.make_guess("foo");

        // Lahja makes a guess
        _sender_source.set_sender(LAHJA);
        egg.make_guess("foo");

        // Bob makes a guess
        _sender_source.set_sender(BOB);
        egg.make_guess("foo");

        //We reveal (done as Bob but shouldn't matter)
        _time_machine.set_now(2000);
        egg.reveal_answer(SALT);

        // Bob claims his reward
        egg.claim_win();
        assertEq(BOB.balance, 1666666666666666666);

        // Alice claims her reward
        _sender_source.set_sender(ALICE);
        egg.claim_win();
        assertEq(ALICE.balance, 1666666666666666667);

        // Lahja claims her reward
        _sender_source.set_sender(LAHJA);
        egg.claim_win();
        assertEq(ALICE.balance, 1666666666666666667);
    }

    function test_two_winner_one_loser_claim_reward() public {
        // Alice (default) makes a guess
        assertEq(ALICE.balance, 0 ether);
        egg.make_guess("foo");

        // Lahja makes a guess
        _sender_source.set_sender(LAHJA);
        egg.make_guess("foo");

        // Bob makes a guess
        _sender_source.set_sender(BOB);
        egg.make_guess("boo");

        //We reveal (done as Bob but shouldn't matter)
        _time_machine.set_now(2000);
        egg.reveal_answer(SALT);

        // Bob claims his reward
        try egg.claim_win() {
            fail();
        } catch Error(string memory reason) {
            assertEq(reason, "You lost the game");
            assertEq(BOB.balance, 0);
        }

        // Alice claims her reward
        _sender_source.set_sender(ALICE);
        egg.claim_win();
        assertEq(ALICE.balance, 2500000000000000000);

        // Lahja claims her reward
        _sender_source.set_sender(LAHJA);
        egg.claim_win();
        assertEq(ALICE.balance, 2500000000000000000);
    }

    receive() external payable { }

}
