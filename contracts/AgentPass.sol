// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal read interface for the SPACE ID Agent ID registry.
/// @dev The registry is an ERC-721 contract on BNB Chain
///      (0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F). Agent IDs are
///      non-transferable and limited to one per person, so
///      `balanceOf(account) > 0` is a reliable "is a verified agent" check.
interface IAgentIdRegistry {
    function balanceOf(address account) external view returns (uint256);
}

/// @title Agent Pass — a daily free claim for Binance Agent ID holders
/// @notice Holders of a Binance Agent ID (a name.ai identity issued through
///         Binance Wallet) can claim one soulbound badge per UTC day, free.
///         Claiming needs no payment and no token approvals, and this
///         contract never holds user funds: `claim()` is non-payable and
///         there is no withdrawal function at all.
///
///         Agent ID is the core of the product, not a decoration:
///           * Eligibility — only Agent ID holders can claim, checked live
///             against the official registry on every claim.
///           * Fairness — Agent IDs are one-per-person and non-transferable,
///             so "one claim per address per day" is also "one claim per
///             person per day". Sybil resistance comes from the identity
///             layer instead of captchas or allowlists.
///           * Streaks — consecutive-day claims build a public streak that
///             belongs to a persistent agent identity.
///
/// @dev Owner powers are deliberately minimal: the owner (the deployer) can
///      only pause and unpause claims. There is no owner minting, no fee,
///      no upgrade mechanism and no way to move user assets.
contract AgentPass {
    // ------------------------------------------------------------------
    // ERC-721 metadata
    // ------------------------------------------------------------------
    string public constant name = "Agent Pass";
    string public constant symbol = "APASS";

    // ------------------------------------------------------------------
    // Configuration & ownership
    // ------------------------------------------------------------------

    /// @notice The official Agent ID registry this contract gates on.
    address public immutable agentIdRegistry;

    /// @notice Deployer. Can only pause/unpause claims (see header).
    address public owner;

    /// @notice While true, `claim()` reverts. Badges already minted are
    ///         unaffected (they are soulbound and carry no value transfer).
    bool public paused;

    // ------------------------------------------------------------------
    // Claim accounting
    // ------------------------------------------------------------------

    /// @notice Total number of successful claims, all time.
    uint256 public totalClaims;

    /// @notice UTC day index (block.timestamp / 86400) of an address's
    ///         most recent claim. 0 means "never claimed" — safe, because
    ///         day 0 (1970-01-01) can never be "today" again.
    mapping(address => uint256) public lastClaimDay;

    /// @dev Current consecutive-day streak per address.
    mapping(address => uint256) private _streaks;

    /// @dev Total claims per address.
    mapping(address => uint256) private _claimsPerAddress;

    /// @dev Every address that has ever claimed, in first-claim order.
    address[] private _claimers;

    // ------------------------------------------------------------------
    // Soulbound ERC-721 storage
    // ------------------------------------------------------------------

    uint256 private _nextTokenId = 1;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    /// @dev UTC day index on which each badge was minted (encoded in URI).
    mapping(uint256 => uint256) private _mintDay;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    /// @notice Emitted on every successful claim.
    event Claimed(
        address indexed claimer,
        uint256 indexed tokenId,
        uint256 day,
        uint256 streak
    );

    /// @dev Standard ERC-721 mint event (transfers are disabled, see below).
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );

    event Paused(address indexed by);
    event Unpaused(address indexed by);

    modifier onlyOwner() {
        require(msg.sender == owner, "AgentPass: not the owner");
        _;
    }

    constructor(address registry_) {
        require(registry_ != address(0), "AgentPass: registry is zero address");
        agentIdRegistry = registry_;
        owner = msg.sender;
    }

    // ------------------------------------------------------------------
    // The claim
    // ------------------------------------------------------------------

    /// @notice Claim today's badge. Free: no payment is accepted and no
    ///         approval is needed. Reverts if claims are paused, if the
    ///         caller holds no Agent ID, or if the caller already claimed
    ///         today (UTC).
    /// @return tokenId The id of the freshly minted soulbound badge.
    function claim() external returns (uint256 tokenId) {
        require(!paused, "AgentPass: claims are paused");
        require(hasAgentId(msg.sender), "AgentPass: caller holds no Agent ID");

        uint256 today = currentDay();
        require(
            lastClaimDay[msg.sender] != today,
            "AgentPass: already claimed today"
        );

        // Streak: claiming the day after your last claim extends the
        // streak; a gap of one or more missed days restarts it at 1.
        if (lastClaimDay[msg.sender] == today - 1) {
            _streaks[msg.sender] += 1;
        } else {
            _streaks[msg.sender] = 1;
        }

        // First-ever claim from this address: record a new unique claimer.
        if (_claimsPerAddress[msg.sender] == 0) {
            _claimers.push(msg.sender);
        }

        tokenId = _nextTokenId++;
        _owners[tokenId] = msg.sender;
        _balances[msg.sender] += 1;
        _mintDay[tokenId] = today;

        lastClaimDay[msg.sender] = today;
        _claimsPerAddress[msg.sender] += 1;
        totalClaims += 1;

        emit Transfer(address(0), msg.sender, tokenId);
        emit Claimed(msg.sender, tokenId, today, _streaks[msg.sender]);
    }

    // ------------------------------------------------------------------
    // Views used by the web page (and anyone else)
    // ------------------------------------------------------------------

    /// @notice True if `account` currently holds at least one Agent ID.
    function hasAgentId(address account) public view returns (bool) {
        return IAgentIdRegistry(agentIdRegistry).balanceOf(account) > 0;
    }

    /// @notice True if `account` could successfully claim right now.
    function canClaimToday(address account) public view returns (bool) {
        return
            !paused &&
            hasAgentId(account) &&
            lastClaimDay[account] != currentDay();
    }

    /// @notice Current consecutive-day claim streak of `account`.
    function streakOf(address account) public view returns (uint256) {
        return _streaks[account];
    }

    /// @notice Total number of claims made by `account`, all time.
    function claimsOf(address account) public view returns (uint256) {
        return _claimsPerAddress[account];
    }

    /// @notice Number of distinct addresses that have ever claimed.
    function uniqueClaimers() public view returns (uint256) {
        return _claimers.length;
    }

    /// @notice The unique claimer stored at `index` (first-claim order).
    function claimerAt(uint256 index) public view returns (address) {
        require(index < _claimers.length, "AgentPass: index out of range");
        return _claimers[index];
    }

    /// @notice The current UTC day index (days since the Unix epoch).
    function currentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @notice The UTC day index on which badge `tokenId` was minted.
    function dayOf(uint256 tokenId) public view returns (uint256) {
        require(_owners[tokenId] != address(0), "AgentPass: nonexistent token");
        return _mintDay[tokenId];
    }

    // ------------------------------------------------------------------
    // Owner controls — pause/unpause only, by design
    // ------------------------------------------------------------------

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // ------------------------------------------------------------------
    // Soulbound ERC-721 surface
    //
    // Badges are proof of showing up, not assets: every transfer and
    // approval function reverts. Minting happens only inside `claim()`.
    // ------------------------------------------------------------------

    function balanceOf(address account) public view returns (uint256) {
        require(account != address(0), "AgentPass: zero address");
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0), "AgentPass: nonexistent token");
        return tokenOwner;
    }

    function transferFrom(address, address, uint256) public pure {
        revert("AgentPass: badges are soulbound and cannot be transferred");
    }

    function safeTransferFrom(address, address, uint256) public pure {
        revert("AgentPass: badges are soulbound and cannot be transferred");
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure {
        revert("AgentPass: badges are soulbound and cannot be transferred");
    }

    function approve(address, uint256) public pure {
        revert("AgentPass: badges are soulbound and cannot be approved");
    }

    function setApprovalForAll(address, bool) public pure {
        revert("AgentPass: badges are soulbound and cannot be approved");
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "AgentPass: nonexistent token");
        return address(0);
    }

    function isApprovedForAll(address, address) public pure returns (bool) {
        return false;
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC-165
            interfaceId == 0x80ac58cd || // ERC-721
            interfaceId == 0x5b5e139f; // ERC-721 metadata
    }

    // ------------------------------------------------------------------
    // Token URI — fully self-contained (data URI, no external hosting)
    // ------------------------------------------------------------------

    /// @notice JSON metadata + SVG artwork for a badge, returned as a
    ///         base64 data URI. The artwork names the day the badge was
    ///         earned, which is also exposed as a metadata attribute.
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_owners[tokenId] != address(0), "AgentPass: nonexistent token");
        uint256 day = _mintDay[tokenId];

        string memory svg = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' width='400' height='400' viewBox='0 0 400 400'>",
                "<rect width='400' height='400' rx='24' fill='#0B0E11'/>",
                "<rect x='16' y='16' width='368' height='368' rx='18' fill='none' stroke='#F0B90B' stroke-width='3'/>",
                "<text x='200' y='150' font-family='Arial, sans-serif' font-size='36' font-weight='bold' fill='#F0B90B' text-anchor='middle'>AGENT PASS</text>",
                "<text x='200' y='220' font-family='Arial, sans-serif' font-size='28' fill='#EAECEF' text-anchor='middle'>Day ",
                _toString(day),
                "</text>",
                "<text x='200' y='272' font-family='Arial, sans-serif' font-size='20' fill='#848E9C' text-anchor='middle'>Badge #",
                _toString(tokenId),
                "</text>",
                "</svg>"
            )
        );

        string memory json = string(
            abi.encodePacked(
                '{"name":"Agent Pass #',
                _toString(tokenId),
                '","description":"A soulbound badge earned by a Binance Agent ID holder for claiming on this day with Agent Pass.",',
                '"image":"data:image/svg+xml;base64,',
                _base64Encode(bytes(svg)),
                '","attributes":[',
                '{"trait_type":"Day","value":',
                _toString(day),
                '},{"trait_type":"Badge","value":',
                _toString(tokenId),
                "}]}"
            )
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    _base64Encode(bytes(json))
                )
            );
    }

    // ------------------------------------------------------------------
    // Small pure helpers
    // ------------------------------------------------------------------

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /// @dev Standard base64 encoding (RFC 4648), used for data URIs.
    function _base64Encode(bytes memory data)
        internal
        pure
        returns (string memory)
    {
        if (data.length == 0) return "";
        string
            memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        string memory result = new string(encodedLen + 32);
        assembly {
            mstore(result, encodedLen)
            let tablePtr := add(table, 1)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(result, 32)
            for {

            } lt(dataPtr, endPtr) {

            } {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                mstore8(
                    resultPtr,
                    mload(add(tablePtr, and(shr(18, input), 0x3F)))
                )
                resultPtr := add(resultPtr, 1)
                mstore8(
                    resultPtr,
                    mload(add(tablePtr, and(shr(12, input), 0x3F)))
                )
                resultPtr := add(resultPtr, 1)
                mstore8(
                    resultPtr,
                    mload(add(tablePtr, and(shr(6, input), 0x3F)))
                )
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1)
            }
            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 2), 0x3d)
                mstore8(sub(resultPtr, 1), 0x3d)
            }
            case 2 {
                mstore8(sub(resultPtr, 1), 0x3d)
            }
        }
        return result;
    }
}
