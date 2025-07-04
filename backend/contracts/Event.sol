// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
// Don't forget to import SafeMath if you are using Solidity <0.8.0 for arithmetic safety with `add`, `mul`, `div`
// If using Solidity 0.8.0+, arithmetic overflow/underflow is checked by default, so SafeMath is not strictly necessary for basic operations.
// Given your pragma is >=0.7.0 <0.9.0, you might be on 0.8.x, so it's safer. Let's assume you're on 0.8.x or will handle safety.


contract Event is ERC721, Ownable, ReentrancyGuard, Pausable {
    using Strings for uint256;

    // Control Event Status at a granular level
    enum Stages {
        Prep,           // 0 - Preparation stage, cannot buy tickets
        Active,         // 1 - Active stage, users can buy tickets
        CheckinOpen,    // 2 - Check-in Open, tickets can be marked as used (entry)
        Cancelled,      // 3 - Cancelled, refunds can be processed
        Ended           // 4 - Closed, event ended
    }
    enum TicketStatus { Valid, Used, AvailableForSale }

    struct Ticket {
        uint resalePrice;
        TicketStatus status;
    }

    Ticket[] public tickets;
    uint public price;
    uint public markupPercent; // MAX 10%
    uint public numTicketsLeft;
    uint public numTickets;
    bool public canBeResold;
    bool public publicIsCancelled; // Consider if you need both publicIsCancelled and isCancelled
    bool public isCancelled;
    bool public canceled = false;


    string public eventMetadataURI;

    mapping(address => uint) public balances;
    mapping(address => bool) public isUserRefundProcessed;
    mapping(uint => string) public tokenURIs;

    Stages public stage;

    // --- Time-based Event Parameters ---
    uint public eventStartTime;
    uint public eventEndTime;
    uint public ticketSalesEndTime;

    // EVENTS
    event CreateTicket(address contractAddress, string eventName, address buyer, uint ticketID);
    event WithdrawMoney(address receiver, uint amount);
    event OwnerWithdrawMoney(address ownerAddress, uint amount);
    event TicketForSale(address seller, uint ticketID, uint resalePrice);
    event TicketSold(address contractAddress, string eventName, address buyer, uint ticketID);
    event TicketUsed(address contractAddress, uint ticketID, string eventName);
    event StageChanged(Stages oldStage, Stages newStage);
    event TicketSaleCancelled(address indexed seller, uint256 indexed ticketId);

    constructor(
        address _owner,
        uint _numTickets,
        uint _price,
        bool _canBeResold,
        uint _markupPercent,
        string memory _eventName,
        string memory _eventSymbol,
        string memory _eventMetadataURI,
        uint _eventStartTime,
        uint _eventEndTime,
        uint _ticketSalesEndTime
    ) ERC721(_eventName, _eventSymbol) Ownable(_owner) {
        require(_markupPercent <= 10, "Markup must be max 10%");
        require(_numTickets > 0, "Must create > 0 tickets");
        require(_eventStartTime > block.timestamp, "Event start time must be in the future.");
        require(_eventEndTime > _eventStartTime, "Event end time must be after start time.");
        require(_ticketSalesEndTime < _eventStartTime, "Ticket sales must end before event starts.");
        require(_ticketSalesEndTime > block.timestamp, "Ticket sales end time must be in the future.");

        numTicketsLeft = _numTickets;
        numTickets = _numTickets;
        price = _price;
        canBeResold = _canBeResold;
        markupPercent = _markupPercent;
        stage = Stages.Prep;
        eventMetadataURI = _eventMetadataURI;
        eventStartTime = _eventStartTime;
        eventEndTime = _eventEndTime;
        ticketSalesEndTime = _ticketSalesEndTime;
    }

    function buyTicket(string memory _tokenURI)
        public
        payable
        requiredStage(Stages.Active)
        whenNotPaused
    {
        require(numTicketsLeft > 0, "Sold out");
        require(msg.value >= price, "Not enough ETH sent for ticket price");
        require(block.timestamp < ticketSalesEndTime, "Ticket sales period has ended.");

        tickets.push(Ticket(0, TicketStatus.Valid));
        uint ticketID = tickets.length - 1;
        numTicketsLeft--;

        if (msg.value > price) {
            balances[msg.sender] += msg.value - price;
        }
        balances[owner()] += price;

        _safeMint(msg.sender, ticketID);
        tokenURIs[ticketID] = _tokenURI;

        emit CreateTicket(address(this), name(), msg.sender, ticketID);
    }

    function setTicketToUsed(uint ticketID)
        public
        onlyOwner
        requiredStage(Stages.CheckinOpen)
    {
        require(ownerOf(ticketID) != address(0), "ERC721: invalid token ID or token already burned.");
        require(tickets[ticketID].status == TicketStatus.Valid || tickets[ticketID].status == TicketStatus.AvailableForSale, "Ticket not valid or already used");

        tickets[ticketID].status = TicketStatus.Used;
        _burn(ticketID);
        emit TicketUsed(address(this), ticketID, name());
    }

    function setTicketForSale(uint ticketID, uint resalePrice)
        public
        ownsTicket(ticketID)
        requiredStage(Stages.Active)
        whenNotPaused
    {
        require(tickets[ticketID].status != TicketStatus.Used, "Used ticket cannot be resold");
        require(canBeResold, "Resale not allowed for this event");
        require(resalePrice > 0, "Resale price must be greater than 0");

        // *** MODIFIED LINE HERE ***
        // MAX resale price = price * (1 + markupPercent / 100)
        uint256 maxAllowedResalePrice = (price * (100 + markupPercent)) / 100;
        require(resalePrice <= maxAllowedResalePrice, string(abi.encodePacked(
            "Resale price exceeds maximum allowed markup of ",
            Strings.toString(markupPercent),
            "%"
        )));
        tickets[ticketID].status = TicketStatus.AvailableForSale;
        tickets[ticketID].resalePrice = resalePrice;

        emit TicketForSale(msg.sender, ticketID, resalePrice);
    }

    function buyTicketFromUser(uint ticketID, string memory _newTokenURI)
        public
        payable
        requiredStage(Stages.Active)
        whenNotPaused
    {
        require(tickets[ticketID].status == TicketStatus.AvailableForSale, "Ticket not for sale");

        uint ticketResalePrice = tickets[ticketID].resalePrice;
        require(msg.value >= ticketResalePrice, "Not enough ETH sent for resale price");

        address payable seller = payable(ownerOf(ticketID));
        require(seller != address(0), "Ticket does not exist or has been burned.");
        require(msg.sender != seller, "Cannot buy your own ticket.");

        if (msg.value > ticketResalePrice) {
            balances[msg.sender] += msg.value - ticketResalePrice;
        }

        // 🚀 Full amount to seller
        balances[seller] += ticketResalePrice;

        _transfer(seller, msg.sender, ticketID);
        tokenURIs[ticketID] = _newTokenURI;

        tickets[ticketID].status = TicketStatus.Valid;
        emit TicketSold(address(this), name(), msg.sender, ticketID);
    }


    function cancelTicketSale(uint256 _ticketId)
        public
        ownsTicket(_ticketId)
        whenNotPaused
    {
        require(tickets[_ticketId].status == TicketStatus.AvailableForSale, "Ticket is not currently listed for sale.");

        tickets[_ticketId].status = TicketStatus.Valid;

        tickets[_ticketId].resalePrice = 0;

        emit TicketSaleCancelled(msg.sender, _ticketId);
    }


    function withdraw() public nonReentrant {
        uint amount = balances[msg.sender];

        if (msg.sender != owner() && stage == Stages.Cancelled && !isUserRefundProcessed[msg.sender]) {
            uint userTicketsCount = balanceOf(msg.sender);
            if (userTicketsCount > 0) {
                amount += userTicketsCount * price;
                isUserRefundProcessed[msg.sender] = true;
            }
        }

        require(amount > 0, "Nothing to withdraw");

        balances[msg.sender] = 0;

        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Withdraw failed");

        if (msg.sender == owner()) {
            emit OwnerWithdrawMoney(msg.sender, amount);
        } else {
            emit WithdrawMoney(msg.sender, amount);
        }
    }

    function setStage(Stages _stage) public onlyOwner returns (Stages) {
        require(stage != Stages.Cancelled, "Cannot change stage after event is Cancelled.");


        Stages oldStage = stage;
        stage = _stage;

        if (_stage == Stages.Cancelled) {
            isCancelled = true;
        } else if (_stage == Stages.Active) {
            require(block.timestamp < ticketSalesEndTime, "Cannot activate sales; sales period has ended.");
        } else if (_stage == Stages.CheckinOpen) {
            require(block.timestamp >= eventStartTime && block.timestamp < eventEndTime, "Check-in can only open during event hours.");
        } else if (_stage == Stages.Ended) {
            require(block.timestamp >= eventEndTime, "Cannot close event before it ends.");
        }

        emit StageChanged(oldStage, stage);
        return stage;
    }

    function getTicketStatus(uint ticketID) external view returns (TicketStatus) {
        require(ticketID < tickets.length, "Invalid ticket ID");
        return tickets[ticketID].status;
    }

    function tokenURI(uint tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return tokenURIs[tokenId];
    }

    function getOrganizer() public view returns (address) {
        return owner();
    }

    function getMyTickets() public view returns (uint256[] memory) {
        uint count = 0;
        for (uint i = 0; i < numTickets; i++) {
            try this.ownerOf(i) returns (address ticketOwner) {
                if (ticketOwner == msg.sender) {
                    count++;
                }
            } catch {
                // If ownerOf reverts (e.g., token burned), it means the token is not owned by anyone.
                // We simply skip it.
            }
        }

        uint256[] memory myTickets = new uint256[](count);
        uint index = 0;
        for (uint i = 0; i < numTickets; i++) {
            try this.ownerOf(i) returns (address ticketOwner) {
                if (ticketOwner == msg.sender) {
                    myTickets[index] = i;
                    index++;
                }
            } catch {
                // Skip
            }
        }
        return myTickets;
    }

    function cancelEvent() external onlyOwner {
        require(stage == Stages.Prep, "Can only cancel event in Prep stage.");
        canceled = true;
        stage = Stages.Cancelled;
    }

    function getTicketsForSale() public view returns (uint[] memory) {
        uint count = 0;
        for (uint i = 0; i < tickets.length; i++) {
            if (tickets[i].status == TicketStatus.AvailableForSale) {
                count++;
            }
        }

        uint[] memory ticketsForSale = new uint[](count);
        uint index = 0;
        for (uint i = 0; i < tickets.length; i++) {
            if (tickets[i].status == TicketStatus.AvailableForSale) {
                ticketsForSale[index] = i;
                ticketsForSale[index] = i;
                index++;
            }
        }

        return ticketsForSale;
    }

    function getTicketResalePrice(uint ticketID) public view returns (uint) {
        require(ticketID < tickets.length, "Invalid ticket ID");
        return tickets[ticketID].resalePrice;
    }


    // --- Modifiers ---
    modifier requiredStage(Stages _stage) {
        require(stage == _stage, string(abi.encodePacked("Invalid stage. Current stage: ", uint256(stage).toString(), ", Required: ", uint256(_stage).toString())));
        _;
    }

    modifier ownsTicket(uint ticketID) {
        require(ownerOf(ticketID) == msg.sender, "Not your ticket");
        _;
    }

    // --- Pausable Functions ---
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}