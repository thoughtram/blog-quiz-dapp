pragma solidity ^0.6.7;

import "ds-test/test.sol";

interface ITimeSource {
  function get_now() external returns (uint);
}

contract DefaultTimeSource is ITimeSource{
  function get_now() public override returns (uint) {
    return now;
  }
}

interface ISenderSource {
  function get_sender(address payable sender) external returns (address payable);
}

contract DefaultSender is ISenderSource{
  function get_sender(address payable who) public override returns (address payable) {
    return who;
  }
}

enum GameState {
  Started,
  RevealPeriod,
  Revealed,
  Scammed
}

contract Quiz {
  // For debugging
  event log_bytes32 (bytes32);
  event log_address (address payable);
  event log_named_uint (bytes32 key, uint val);

  bool _revealed;
  ITimeSource private _time_source;
  ISenderSource private _sender_source;

  // block time from when reveal epoch *should* start
  uint private _reveal_epoch;

  // block time from when people can call us scammers if we have *NOT* revealed by then.
  // Everyone will be able to call `get_my_money_back` at that point.
  uint private _scam_epoch;

  // keccak256(guess + salt) have to result in the following hash to win the quiz
  bytes32 private _winning_hash;

  //TODO: Probably get rid of all string types

  // The salt will only be known once we reveal, making it impossible for participants to
  // check if they got it right *before* we reveal the answer
  string private _salt;

  // Map players to their guesses. We remove players as soon as they claimed their profit.
  mapping(address => string) private _active_player_guesses;

  // Count how many addresses made the same guess. This is important to efficiently
  // calculate proportional payouts. We substract counts whenever we pay out players.
  mapping(string => uint) private _guess_tally;


  constructor(ITimeSource time_source,
              ISenderSource sender_source,
              uint reveal_epoch,
              uint scam_epoch,
              bytes32 winning_hash
              ) public payable {

    _revealed = false;
    _time_source = time_source;
    _sender_source = sender_source;
    _reveal_epoch = reveal_epoch;
    _scam_epoch = scam_epoch;
    _winning_hash = winning_hash;
  }


  function get_state() public returns (GameState) {
    if (_revealed) {
      return GameState.Revealed;
    }
    if (_time_source.get_now() < _reveal_epoch) {
      return GameState.Started;
    } else if (_time_source.get_now() < _scam_epoch) {
      return GameState.RevealPeriod;
    } else if (_time_source.get_now() >= _scam_epoch) {
      return GameState.Scammed;
    }
  }

  function made_guess(address someone) private view returns (bool) {
    return bytes(_active_player_guesses[someone]).length != 0;
  }

  // TODO: Everything :)
  function make_guess(string memory guess) public {
    if (made_guess(get_sender())) {
      revert("Already placed your guess!");
    }

    if (get_state() != GameState.Started) {
      revert("Can not place guess in current game phase");
    }

    _active_player_guesses[get_sender()] = guess;
    _guess_tally[guess]++;
  }

  function claim_win() public {

    if (!made_guess(get_sender())){
      revert("Not a player");
    }

    GameState state = get_state();
    if (state == GameState.Started || state == GameState.RevealPeriod) {
      revert("Be patient! The game is still running.");
    } else if (state == GameState.Revealed) {
      bytes32 final_hash = keccak256(abi.encodePacked(_active_player_guesses[get_sender()], _salt));
      emit log_bytes32(final_hash);
      if (final_hash == _winning_hash) {
        string memory guess = _active_player_guesses[get_sender()];
        uint current_guess_tally = _guess_tally[guess];
        // TODO: THIS IS PROBABLY PROBLEMATIC
        uint payout = address(this).balance / current_guess_tally;
        // We delete the player as a simple way to protect from reentrancy attacks
        delete _active_player_guesses[get_sender()];
        // We reduce the count for this specific guess when we pay it out to keep
        // the calculation of proportional payouts simple.
        _guess_tally[guess]--;

        get_sender().transfer(payout);
      }
      else {
        revert("You lost");
      }
    } else if (state == GameState.Scammed) {
      // TODO: Need to proportional pay back fund
      revert("Not implemented");
    }
  }

  function get_sender() private returns (address payable) {
    // In production, this just echos msg.sender back to us but during testing, we can
    // mock different users to test complex scenarios.
    return _sender_source.get_sender(msg.sender);
  }

  function reveal_answer(string memory salt) public {
    GameState state = get_state();
    if (state == GameState.Revealed) {
      revert("Already revealed. Can not reveal again!");
    } else if (state == GameState.Started) {
      revert("Can not reveal before reveal_epoch started");
    } else if (state == GameState.Scammed) {
      revert("Too late scammer!");
    } else if (state == GameState.RevealPeriod) {
      _revealed = true;
      _salt = salt;
    } else {
      revert("Invariant");
    }

  }

}
