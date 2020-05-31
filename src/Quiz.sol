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
  Scammed,
  WinnerNoShow
}

contract Quiz {
  // For debugging
  event log_bytes32 (bytes32);
  event log_address (address payable);
  event log_named_uint (bytes32 key, uint val);
  // TODO: Think about useful events to emit

  bool _revealed;
  ITimeSource private _time_source;
  ISenderSource private _sender_source;

  // block time from when reveal epoch *should* start
  uint private _reveal_epoch;

  // block time from when people can call us scammers if we have *NOT* revealed by then.
  // Everyone will be able to call `claim_prize` at that point to claim an equal amount
  // of the overall jackpot.
  uint private _scam_epoch;

  // block time from when *everyone* will be able to claim an equal amount of the overall
  // jackpot in case no winner showed up to claim their prize until now.
  uint private _winner_no_show_epoch;

  // The winning hash is cemented in as: keccak256((keccak256(winning_phrase), salt))
  // This means players do not reveal their plain text guess to other players.
  // Instead they only commit to the hash of their guess.
  // That said, when we end the game by revealing, we do reveal the plain text winning phrase.
  bytes32 private _winning_hash;

  // The salt will only be known once we reveal, making it impossible for participants to
  // check if their guess is correct *before* we reveal the answer.
  bytes32 private _salt;

  // Map players to their guess hashes. We remove players as soon as they claimed their profit.
  mapping(address => bytes32) private _active_player_guesses;

  // Count how many addresses made the same guess. This is important to efficiently
  // calculate proportional payouts. We substract counts whenever we pay out players.
  mapping(bytes32 => uint) private _guess_tally;

  // We keep a count of all guesses incase we have to split the pot equally across all players.
  // Again, we decrement this as we pay out money to keep things simple.
  uint private _guess_count;


  constructor(ITimeSource time_source,
              ISenderSource sender_source,
              uint reveal_epoch,
              uint scam_epoch,
              uint winner_no_show_epoch,
              bytes32 winning_hash
              ) public payable {

    _revealed = false;
    _time_source = time_source;
    _sender_source = sender_source;
    _reveal_epoch = reveal_epoch;
    _scam_epoch = scam_epoch;
    _winner_no_show_epoch = winner_no_show_epoch;
    _winning_hash = winning_hash;
  }

  // =======PRIVATE FUNCTIONS=======
  function has_made_guess(address someone) private view returns (bool) {
    return _active_player_guesses[someone] != bytes32("");
  }

  function pay_player(address payable player, uint amount) private {
    bytes32 guess_hash = _active_player_guesses[player];
    // After payout we delete the player and decrement the two different counters.
    // This prevents the player from claiming prizes multiple times. Decrementing the counters
    // makes it simple to calculate the continuing payouts for other players.
    delete _active_player_guesses[player];
    _guess_tally[guess_hash]--;
    _guess_count--;
    // payout is the very last step to prevent reentrency attacks
    player.transfer(amount);
  }

  function get_sender() private returns (address payable) {
    // In production, this just echos msg.sender back to us but during testing, we can
    // mock different users to test complex scenarios.
    return _sender_source.get_sender(msg.sender);
  }

  // =======PUBLIC APIS=======

  function get_state() public returns (GameState) {
    uint this_moment = _time_source.get_now();
    if (_revealed) {
      if (this_moment < _winner_no_show_epoch) {
        return GameState.Revealed;
      }
      return GameState.WinnerNoShow;
    }
    if (this_moment < _reveal_epoch) {
      return GameState.Started;
    } else if (this_moment < _scam_epoch) {
      return GameState.RevealPeriod;
    } else if (this_moment >= _scam_epoch) {
      return GameState.Scammed;
    }

    revert("Invariant");
  }

  function make_guess(bytes32 guess_hash) public {
    address payable player = get_sender();
    if (has_made_guess(player)) {
      revert("Already placed your guess!");
    }

    if (get_state() != GameState.Started) {
      revert("Can not place guess in current game phase");
    }

    _active_player_guesses[player] = guess_hash;
    _guess_tally[guess_hash]++;
    _guess_count++;
  }

  function claim_prize() public {

    address payable player = get_sender();

    if (!has_made_guess(player)){
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
        revert("Not a winner. Wait until winner-no-show-period to still claim a prize");
      }
    } else if (state == GameState.WinnerNoShow) {
      uint256 payout = SafeMath.div(address(this).balance, _guess_count);
      pay_player(player, payout);
    } else if (state == GameState.Scammed) {
      uint256 payout = SafeMath.div(address(this).balance, _guess_count);
      pay_player(player, payout);
    }
  }

  function is_winning_guess_hash(bytes32 guess_hash,
                                 bytes32 salt,
                                 bytes32 winning_hash) public pure returns (bool) {
      return keccak256(abi.encodePacked(guess_hash, salt)) == winning_hash;
  }

  function create_winning_hash(string memory winning_phrase,
                               bytes32 salt) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(keccak256(bytes(winning_phrase)), salt));
  }

  function reveal_answer(string memory winning_phrase, bytes32 salt) public {
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
