// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract CommitRevealBounty {
    enum Phase { Commit, Reveal, Judging, Finalized }

    struct Bounty {
        address owner;
        string question;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        Phase phase;
        address winner;
    }

    uint256 public bountyCount;
    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => string[]) public revealedAnswers;
    mapping(uint256 => address[]) public revealedParticipants;
    mapping(uint256 => mapping(address => bytes32)) public commitments;
    mapping(uint256 => mapping(address => bool)) public revealed;

    event BountyCreated(uint256 indexed bountyId, address owner, uint256 reward);
    event CommitmentSubmitted(uint256 indexed bountyId, address participant);
    event AnswerRevealed(uint256 indexed bountyId, address participant, string answer);
    event JudgingStarted(uint256 indexed bountyId, string[] answers, address[] participants);
    event WinnerFinalized(uint256 indexed bountyId, address winner);

    function createBounty(string calldata question, uint256 commitDuration, uint256 revealDuration)
        external payable returns (uint256 id)
    {
        require(msg.value > 0, "Need reward");
        id = bountyCount++;
        bounties[id] = Bounty(msg.sender, question, msg.value,
            block.timestamp + commitDuration,
            block.timestamp + commitDuration + revealDuration,
            Phase.Commit, address(0));
        emit BountyCreated(id, msg.sender, msg.value);
    }

    function submitCommitment(uint256 bountyId, bytes32 commitment) external {
        Bounty storage b = bounties[bountyId];
        require(b.phase == Phase.Commit && block.timestamp <= b.commitDeadline, "Not commit phase");
        require(commitments[bountyId][msg.sender] == bytes32(0), "Already committed");
        commitments[bountyId][msg.sender] = commitment;
        emit CommitmentSubmitted(bountyId, msg.sender);
    }

    function revealAnswer(uint256 bountyId, string calldata answer, bytes32 salt) external {
        Bounty storage b = bounties[bountyId];
        require(block.timestamp > b.commitDeadline && block.timestamp <= b.revealDeadline, "Not reveal phase");
        require(!revealed[bountyId][msg.sender], "Already revealed");
        require(keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId)) == commitments[bountyId][msg.sender], "Hash mismatch");
        if (b.phase == Phase.Commit) b.phase = Phase.Reveal;
        revealed[bountyId][msg.sender] = true;
        revealedAnswers[bountyId].push(answer);
        revealedParticipants[bountyId].push(msg.sender);
        emit AnswerRevealed(bountyId, msg.sender, answer);
    }

    function judgeAll(uint256 bountyId, bytes calldata) external {
        Bounty storage b = bounties[bountyId];
        require(msg.sender == b.owner, "Not owner");
        require(block.timestamp > b.revealDeadline, "Reveal not over");
        require(revealedAnswers[bountyId].length > 0, "No answers");
        b.phase = Phase.Judging;
        emit JudgingStarted(bountyId, revealedAnswers[bountyId], revealedParticipants[bountyId]);
    }

    function finalizeWinner(uint256 bountyId, uint256 winnerIndex) external {
        Bounty storage b = bounties[bountyId];
        require(msg.sender == b.owner && b.phase == Phase.Judging, "Not allowed");
        require(winnerIndex < revealedParticipants[bountyId].length, "Bad index");
        b.winner = revealedParticipants[bountyId][winnerIndex];
        b.phase = Phase.Finalized;
        (bool ok,) = b.winner.call{value: b.reward}("");
        require(ok, "Transfer failed");
        emit WinnerFinalized(bountyId, b.winner);
    }

    function makeHash(string calldata answer, bytes32 salt, address participant, uint256 bountyId)
        external pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(answer, salt, participant, bountyId));
    }
}
