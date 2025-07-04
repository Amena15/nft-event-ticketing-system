// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "./Event.sol"; // Import the Event contract

contract NFTticketing {
    address public owner;

    Event[] public events;
    event CreateEvent(address _creator, address _event);

    constructor() {
        owner = msg.sender;
    }

    function createEvent(
        uint _numTickets,
        uint _price,
        bool _canBeResold,
        uint _royaltyPercent,
        string memory _eventName,
        string memory _eventSymbol,
        string memory _eventMetadataURI,
        uint _eventStartTime,
        uint _eventEndTime,
        uint _ticketSalesEndTime
    ) external returns (address newEvent) {
        // Ensure event start time is in the future
        require(_eventStartTime > block.timestamp, "Event start time must be in the future.");
        // Ensure event end time is after start time
        require(_eventEndTime > _eventStartTime, "Event end time must be after start time.");
        // Ensure ticket sales end time is before event start time
        require(_ticketSalesEndTime < _eventStartTime, "Ticket sales must end before event starts.");
        
        Event e = new Event(
            tx.origin, // Using tx.origin as the initial owner/organizer
            _numTickets,
            _price,
            _canBeResold,
            _royaltyPercent,
            _eventName,
            _eventSymbol,
            _eventMetadataURI,
            _eventStartTime,
            _eventEndTime,
            _ticketSalesEndTime
        );

        events.push(e);
        emit CreateEvent(msg.sender, address(e));
        return address(e);
    }

    function getEvents() external view returns (address[] memory _events) {
        _events = new address[](events.length);
        for (uint i = 0; i < events.length; i++) {
            _events[i] = address(events[i]);
        }
        return _events;
    }
}