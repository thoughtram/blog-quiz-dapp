pragma solidity ^0.6.7;

import "./SafeMath.sol";

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
  mapping(address => bytes32) private _active_player_guesses;

  // Count how many addresses made the same guess. This is important to efficiently
  // calculate proportional payouts. We substract counts whenever we pay out players.
  mapping(bytes32 => uint) private _guess_tally;

  // We keep a count of all guesses incase we have to split the pot equally across all
  uint _guess_count;


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
    return _active_player_guesses[someone] != bytes32("");
  }

  // TODO: Everything :)
  function make_guess(bytes32 guess_hash) public {
    address payable player = get_sender();
    if (made_guess(player)) {
      revert("Already placed your guess!");
    }

    if (get_state() != GameState.Started) {
      revert("Can not place guess in current game phase");
    }

    _active_player_guesses[player] = guess_hash;
    _guess_tally[guess_hash]++;
    _guess_count++;
  }

  function claim_win() public {

    address payable player = get_sender();

    if (!made_guess(player)){
      revert("Not a player");
    }

    GameState state = get_state();
    if (state == GameState.Started || state == GameState.RevealPeriod) {
      revert("Be patient! The game is still running.");
    } else if (state == GameState.Revealed) {

      bytes32 guess_hash = _active_player_guesses[player];
      emit log_bytes32(guess_hash);
      if (is_winning_guess_hash(guess_hash, _salt, _winning_hash)) {
        uint256 payout = SafeMath.div(address(this).balance, _guess_tally[guess_hash]);
        pay_player(player, payout);
      } else {
        //TODO: If this is called after a certain time has passed in which no winner claimed
        //their reward, pay out the common proportional share.
        revert("You lost the game");
      }
    } else if (state == GameState.Scammed) {
      uint256 payout = SafeMath.div(address(this).balance, _guess_count);
      pay_player(player, payout);
    }
  }

  function is_winning_guess_hash(bytes32 guess_hash,
                                 string memory salt,
                                 bytes32 winning_hash) public pure returns (bool) {
      return keccak256(abi.encodePacked(guess_hash, salt)) == winning_hash;
  }

  function create_winning_hash(string memory winning_phrase,
                               string memory salt) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(keccak256(bytes(winning_phrase)), salt));
  }

  function pay_player(address payable player, uint amount) private {
    bytes32 guess_hash = _active_player_guesses[player];
    // We delete the player as a simple way to protect from reentrancy attacks
    delete _active_player_guesses[player];
    // We reduce the count for this specific guess when we pay it out to keep
    // the calculation of proportional payouts simple.
    _guess_tally[guess_hash]--;
    // We reduce the overall count to keep the calculation for general payments simple, too
    _guess_count--;
    // payout is the very last step to prevent reentrency attacks
    player.transfer(amount);
  }

  function get_sender() private returns (address payable) {
    // In production, this just echos msg.sender back to us but during testing, we can
    // mock different users to test complex scenarios.
    return _sender_source.get_sender(msg.sender);
  }

  function reveal_answer(string memory winning_phrase, string memory salt) public {
    GameState state = get_state();
    if (state == GameState.Revealed) {
      revert("Already revealed. Can not reveal again!");
    } else if (state == GameState.Started) {
      revert("Can not reveal before reveal_epoch started");
    } else if (state == GameState.Scammed) {
      revert("Too late scammer!");
    } else if (state == GameState.RevealPeriod) {
      if (create_winning_hash(winning_phrase, salt) != _winning_hash) {
        // The only reason we reveal the winning phrase is so that everyone can see we used
        // a guessable phrase such as "thoughtram <3 Ethereum" and not gibberish such as "x8.jjkd"
        revert("The phrase and salt do not match up with the _winning_hash");
      }
      _revealed = true;
      _salt = salt;
    } else {
      revert("Invariant");
    }

  }

}
