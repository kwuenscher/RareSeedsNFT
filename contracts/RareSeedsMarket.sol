pragma solidity >=0.7.0 <0.9.0;
//pragma solidity >=0.4.22 <0.9.0;

contract RareSeedsMarket {
    address owner;

    string public standard = "RareSeeds";
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    uint256 public seedIndex;

    int64 public maxSeed = 9223372036854775807;
    int64 public minSeed = -9223372036854775808;

    bool public allSeedsAssigned = false;
    uint256 public seedsRemainingToAssign = 0;
    uint256 public mintFee = 3000000000000000;

    mapping(int64 => address) public seedValueToAddress;

    mapping(int64 => string) public seedValueToWorldName;

    mapping(address => uint256) public balanceOf;

    mapping(uint256 => int64) public indexToSeed;

    mapping (int64 => string) public seedValueToUri;

    struct Offer {
        bool isForSale;
        int64 seedValue;
        address seller;
        uint256 minValue;
        address onlySellTo;
    }

    struct Bid {
        bool hasBid;
        int64 seedValue;
        address bidder;
        uint256 value;
    }

    mapping(int64 => Offer) public seedsOfferedForSale;

    mapping(int64 => Bid) public seedBids;

    mapping(address => uint256) public pendingWithdrawals;

    event Assign(address indexed to, int64 seedValue);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event SeedTransfer(
        address indexed from,
        address indexed to,
        int64 seedValue
    );

    event SeedOffered(
        int64 indexed seedValue,
        uint256 minValue,
        address indexed toAddress
    );

    event SeedBidEntered(
        int64 indexed seedValue,
        uint256 value,
        address indexed fromAddress
    );

    event SeedBidWithdrawn(
        int64 indexed seedValue,
        uint256 value,
        address indexed fromAddress
    );

    event SeedBought(
        int64 indexed seedValue,
        uint256 value,
        address indexed fromAddress,
        address indexed toAddress
    );

    event SeedNoLongerForSale(int64 indexed seedValue);

    /* Initializes contract with initial supply tokens to the creator of the contract */
    constructor() {
        owner = msg.sender;
        totalSupply = 512;
        seedsRemainingToAssign = totalSupply;
        name = "RARESEEDS";
        symbol = "RSX";
        decimals = 0;
        seedIndex = 0;
    }

    function updateMintFee(uint256 newValue) public {
        assert(msg.sender != owner);
        mintFee = newValue;
    }

    function setInitialOwner(address to, int64 seedValue) private {
        assert(msg.sender != owner);
        assert(allSeedsAssigned);
        assert(seedValue >= 10000);
        if (seedValueToAddress[seedValue] != to) {
            balanceOf[seedValueToAddress[seedValue]]--;
            seedValueToAddress[seedValue] = to;
            balanceOf[to]++;
            emit Assign(to, seedValue);
        }
    }

    function setInitialOwners(
        address[] calldata addresses,
        int64[] calldata indices
    ) private {
        if (msg.sender != owner) revert();
        uint256 n = addresses.length;
        for (uint256 i = 0; i < n; i++) {
            setInitialOwner(addresses[i], indices[i]);
        }
    }

    function allInitialOwnersAssigned() private {
        if (msg.sender != owner) revert();
        allSeedsAssigned = true;
    }

    function isSeedValid(int64 seedValue) private view returns(bool) {
        return (seedValue <= maxSeed || seedValue >= minSeed || seedValue != 0);
    }

    function getSeed(int64 seedValue, string memory worldName, string memory uri) public payable {
        if (allSeedsAssigned) revert("All seeds assigned.");
        if (seedsRemainingToAssign == 0) revert("no seeds remaining.");
        if (seedIndex > totalSupply) revert("no more seeds remaining.");
        if (isSeedValid(seedValue) == false)
            revert("Seed out of range.");
        if (seedValueToAddress[seedValue] != address(0))
            revert("Already taken.");
        if (msg.value < mintFee) revert("Not enough mint fees supplied");
        seedValueToAddress[seedValue] = msg.sender;
        seedValueToWorldName[seedValue] = worldName;
        seedValueToUri[seedValue] = uri;
        balanceOf[msg.sender]++;
        seedsRemainingToAssign--;
        seedIndex++;
        indexToSeed[seedIndex] = seedValue;
        pendingWithdrawals[owner] += msg.value;
        emit Assign(msg.sender, seedValue);
    }

    function transferSeed(address to, int64 seedValue) private {
        if (!allSeedsAssigned) revert();
        if (seedValueToAddress[seedValue] != msg.sender) revert();
        if (isSeedValid(seedValue) == false)
            revert("Seed out of range.");
        if (seedsOfferedForSale[seedValue].isForSale) {
            seedNoLongerForSale(seedValue);
        }
        seedValueToAddress[seedValue] = to;
        balanceOf[msg.sender]--;
        balanceOf[to]++;

        emit Transfer(msg.sender, to, 1);
        emit SeedTransfer(msg.sender, to, seedValue);
        // Check for the case where there is a bid from the new owner and refund it.
        // Any other bid can stay in place.
        Bid memory bid = seedBids[seedValue];
        if (bid.bidder == to) {
            // Kill bid and refund value
            pendingWithdrawals[to] += bid.value;
            seedBids[seedValue] = Bid(false, seedValue, address(0), 0);
        }
    }

    function seedNoLongerForSale(int64 seedValue) public {
        if (seedValueToAddress[seedValue] != msg.sender) revert();
        if (isSeedValid(seedValue) == false)
            revert("Seed out of range.");
        seedsOfferedForSale[seedValue] = Offer(
            false,
            seedValue,
            msg.sender,
            0,
            address(0)
        );
        emit SeedNoLongerForSale(seedValue);
    }

    function offerSeedForSale(int64 seedValue, uint256 minSalePriceInWei)
    public
    {
        // if (!allSeedsAssigned) revert();
        if (seedValueToAddress[seedValue] != msg.sender) revert("Sender is not owner of seed.");
        if (isSeedValid(seedValue) == false)
            revert("Seed out of range.");
        seedsOfferedForSale[seedValue] = Offer(
            true,
            seedValue,
            msg.sender,
            minSalePriceInWei,
            address(0)
        );
        emit SeedOffered(seedValue, minSalePriceInWei, address(0));
    }

    function offerSeedForSaleToAddress(
        int64 seedValue,
        uint256 minSalePriceInWei,
        address toAddress
    ) private {
        if (!allSeedsAssigned) revert();
        if (seedValueToAddress[seedValue] != msg.sender) revert();
        if (isSeedValid(seedValue) == false)
            revert("Seed out of range.");
        seedsOfferedForSale[seedValue] = Offer(
            true,
            seedValue,
            msg.sender,
            minSalePriceInWei,
            toAddress
        );
        emit SeedOffered(seedValue, minSalePriceInWei, toAddress);
    }

    function buySeed(int64 seedValue) public payable {
        if (!allSeedsAssigned) revert("All seeds assigned.");
        Offer memory offer = seedsOfferedForSale[seedValue];
        if (isSeedValid(seedValue) == false)
            revert("Seed out of range.");
        if (!offer.isForSale) revert("Not for sale"); // seed not actually for sale
        if (offer.onlySellTo != address(0) && offer.onlySellTo != msg.sender)
            revert("seed not supposed to be sold"); // seed not supposed to be sold to this user
        if (msg.value < offer.minValue) revert("Money offered not enough."); // Didn't send enough ETH
        if (offer.seller != seedValueToAddress[seedValue]) revert(); // Seller no longer owner of seed

        address seller = offer.seller;

        seedValueToAddress[seedValue] = msg.sender;
        balanceOf[seller]--;
        balanceOf[msg.sender]++;
        emit Transfer(seller, msg.sender, 1);

        seedNoLongerForSale(seedValue);
        pendingWithdrawals[seller] += msg.value;
        emit SeedBought(seedValue, msg.value, seller, msg.sender);

        // Check for the case where there is a bid from the new owner and refund it.
        // Any other bid can stay in place.
        Bid storage bid = seedBids[seedValue];
        if (bid.bidder == msg.sender) {
            // Kill bid and refund value
            pendingWithdrawals[msg.sender] += bid.value;
            seedBids[seedValue] = Bid(false, seedValue, address(0), 0);
        }
    }

    function withdraw() public payable {
        // if (!allSeedsAssigned) revert();
        uint256 amount = pendingWithdrawals[msg.sender];
        // Remember to zero the pending refund before
        // sending to prevent re-entrancy attacks
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    function enterBidForSeed(int64 seedValue) public payable {
        if (isSeedValid(seedValue) == false)
            revert("Seed out of range.");
        // if (!allSeedsAssigned) revert();
        if (seedValueToAddress[seedValue] == address(0)) revert();
        if (seedValueToAddress[seedValue] == msg.sender) revert();
        if (msg.value == 0) revert();
        Bid memory existing = seedBids[seedValue];
        if (msg.value <= existing.value) revert();
        if (existing.value > 0) {
            // Refund the failing bid
            pendingWithdrawals[existing.bidder] += existing.value;
        }
        seedBids[seedValue] = Bid(true, seedValue, msg.sender, msg.value);
        emit SeedBidEntered(seedValue, msg.value, msg.sender);
    }

    function acceptBidForSeed(int64 seedValue, uint256 minPrice) public {
        if (isSeedValid(seedValue) == false)
            revert("Seed out of range.");
        // if (!allSeedsAssigned) revert();
        if (seedValueToAddress[seedValue] != msg.sender) revert();
        address seller = msg.sender;
        Bid memory bid = seedBids[seedValue];
        if (bid.value == 0) revert();
        if (bid.value < minPrice) revert();

        seedValueToAddress[seedValue] = bid.bidder;
        balanceOf[seller]--;
        balanceOf[bid.bidder]++;
        emit Transfer(seller, bid.bidder, 1);

        seedsOfferedForSale[seedValue] = Offer(
            false,
            seedValue,
            bid.bidder,
            0,
            address(0)
        );
        uint256 amount = bid.value;
        seedBids[seedValue] = Bid(false, seedValue, address(0), 0);
        pendingWithdrawals[seller] += amount;
        emit SeedBought(seedValue, bid.value, seller, bid.bidder);
    }

    function withdrawBidForSeed(int64 seedValue) public {
        if (isSeedValid(seedValue) == false)
            revert("Seed out of range.");
        if (!allSeedsAssigned) revert();
        if (seedValueToAddress[seedValue] == address(0)) revert();
        if (seedValueToAddress[seedValue] == msg.sender) revert();
        Bid memory bid = seedBids[seedValue];
        if (bid.bidder != msg.sender) revert();
        emit SeedBidWithdrawn(seedValue, bid.value, msg.sender);
        uint256 amount = bid.value;
        seedBids[seedValue] = Bid(false, seedValue, address(0), 0);
        // Refund the bid money
        payable(msg.sender).transfer(amount);
    }

    function setSeedUri(int64 seedValue, string memory uri) public {
        if(msg.sender != seedValueToAddress[seedValue]) revert("Sender is not owner");
        seedValueToUri[seedValue] = uri;
    }
}