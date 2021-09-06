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

    int32 public maxSeed = 2147483647;
    int32 public minSeed = -2147483647;

    bool public allSeedsAssigned = false;
    uint256 public seedsRemainingToAssign = 0;


    //mapping (address => uint) public addressToSeedIndex;
    mapping(int32 => address) public seedValueToAddress;

    /* This creates an array with all balances */
    mapping(address => uint256) public balanceOf;

    // This maps the mint index to the seed.
    mapping(uint256 => int32) public indexToSeed;

    struct Offer {
        bool isForSale;
        int32 seedValue;
        address seller;
        uint256 minValue; // in ether
        address onlySellTo; // specify to sell only to a specific person
    }

    struct Bid {
        bool hasBid;
        int32 seedValue;
        address bidder;
        uint256 value;
    }

    // A record of seeds that are offered for sale at a specific minimum value, and perhaps to a specific person
    mapping(int32 => Offer) public seedsOfferedForSale;

    // A record of the highest seed bid
    mapping(int32 => Bid) public seedBids;

    mapping(address => uint256) public pendingWithdrawals;

    event Assign(address indexed to, int32 seedValue);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event SeedTransfer(
        address indexed from,
        address indexed to,
        int32 seedValue
    );

    event SeedOffered(
        int32 indexed seedValue,
        uint256 minValue,
        address indexed toAddress
    );

    event SeedBidEntered(
        int32 indexed seedValue,
        uint256 value,
        address indexed fromAddress
    );

    event SeedBidWithdrawn(
        int32 indexed seedValue,
        uint256 value,
        address indexed fromAddress
    );

    event SeedBought(
        int32 indexed seedValue,
        uint256 value,
        address indexed fromAddress,
        address indexed toAddress
    );

    event SeedNoLongerForSale(int32 indexed seedValue);

    /* Initializes contract with initial supply tokens to the creator of the contract */
    constructor() {
        owner = msg.sender;
        totalSupply = 500; // Update total supply
        seedsRemainingToAssign = totalSupply;
        name = "RARESEEDS"; // Set the name for display purposes
        symbol = "RSX"; // Set the symbol for display purposes
        decimals = 0; // Amount of decimals for display purposes
        seedIndex = 0;
    }

    function setInitialOwner(address to, int32 seedValue) private {
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
        int32[] calldata indices
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

    function isSeedValid(int32 seedValue) private view returns(bool) {
        return (seedValue <= maxSeed || seedValue >= minSeed || seedValue != 0);
    }

    function getSeed(int32 seedValue) public payable {
        if (allSeedsAssigned) revert("All seeds assigned.");
        if (seedsRemainingToAssign == 0) revert("no seeds remaining.");
        if (seedIndex > totalSupply) revert("no more seeds remaining.");
        if (isSeedValid(seedValue) == false)
            revert("Seed out of range.");
        if (seedValueToAddress[seedValue] != address(0))
            revert("Already taken.");

        seedValueToAddress[seedValue] = msg.sender;
        balanceOf[msg.sender]++;
        seedsRemainingToAssign--;
        seedIndex++;
        indexToSeed[seedIndex] = seedValue;
        emit Assign(msg.sender, seedValue);
    }

    // Transfer ownership of a seed to another user without requiring payment
    function transferSeed(address to, int32 seedValue) private {
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

    function seedNoLongerForSale(int32 seedValue) private {
        if (!allSeedsAssigned) revert();
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

    function offerSeedForSale(int32 seedValue, uint256 minSalePriceInWei)
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
        int32 seedValue,
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

    function buySeed(int32 seedValue) public payable {
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

    function enterBidForSeed(int32 seedValue) public payable {
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

    function acceptBidForSeed(int32 seedValue, uint256 minPrice) public {
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

    function withdrawBidForSeed(int32 seedValue) public {
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
}