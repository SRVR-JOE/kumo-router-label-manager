"""Abstract base agent class for KUMO router management system.

This module defines the base agent interface that all agents must implement,
providing standard lifecycle management and event subscription capabilities.
"""

import asyncio
from abc import ABC, abstractmethod
from typing import Optional, Set
import logging

from ..models.events import BaseEvent, EventType
from ..coordinator.event_bus import EventBus

logger = logging.getLogger(__name__)


class BaseAgent(ABC):
    """Abstract base class for all agents in the system.

    Agents are autonomous components that perform specific tasks and communicate
    through the event bus. Each agent must implement the abstract methods for
    initialization, event handling, and cleanup.

    Attributes:
        name: Unique name identifying this agent
        event_bus: Event bus for publishing and subscribing to events
    """

    def __init__(self, name: str, event_bus: EventBus) -> None:
        """Initialize the base agent.

        Args:
            name: Unique name for this agent
            event_bus: Event bus instance for communication
        """
        self.name = name
        self.event_bus = event_bus
        self._running = False
        self._event_queue: Optional[asyncio.Queue] = None
        self._event_task: Optional[asyncio.Task] = None
        self._subscribed_events: Set[EventType] = set()

        logger.info("Agent '%s' initialized", self.name)

    @abstractmethod
    async def initialize(self) -> None:
        """Initialize the agent.

        This method is called when the agent is started and should perform
        any necessary setup operations. Subclasses must implement this method.
        """
        pass

    @abstractmethod
    async def handle_event(self, event: BaseEvent) -> None:
        """Handle an event from the event bus.

        This method is called for each event the agent is subscribed to.
        Subclasses must implement event handling logic here.

        Args:
            event: Event to handle
        """
        pass

    @abstractmethod
    async def cleanup(self) -> None:
        """Clean up agent resources.

        This method is called when the agent is stopped and should perform
        any necessary cleanup operations. Subclasses must implement this method.
        """
        pass

    async def start(self) -> None:
        """Start the agent.

        This method initializes the agent, creates the event queue, subscribes
        to events, and starts the event processing loop.
        """
        if self._running:
            logger.warning("Agent '%s' is already running", self.name)
            return

        logger.info("Starting agent '%s'", self.name)

        # Initialize agent
        await self.initialize()

        # Create event queue
        self._event_queue = asyncio.Queue()

        # Subscribe to configured events
        await self._subscribe_to_events()

        # Start event processing task
        self._event_task = asyncio.create_task(self._process_events())

        self._running = True
        logger.info("Agent '%s' started successfully", self.name)

    async def stop(self) -> None:
        """Stop the agent.

        This method stops the event processing loop, unsubscribes from events,
        and performs cleanup operations.
        """
        if not self._running:
            logger.warning("Agent '%s' is not running", self.name)
            return

        logger.info("Stopping agent '%s'", self.name)

        self._running = False

        # Cancel event processing task
        if self._event_task:
            self._event_task.cancel()
            try:
                await self._event_task
            except asyncio.CancelledError:
                pass

        # Unsubscribe from events
        await self._unsubscribe_from_events()

        # Clean up agent resources
        await self.cleanup()

        logger.info("Agent '%s' stopped successfully", self.name)

    def subscribe(self, event_type: EventType) -> None:
        """Subscribe to a specific event type.

        Args:
            event_type: Type of events to subscribe to
        """
        if event_type not in self._subscribed_events:
            self._subscribed_events.add(event_type)
            logger.debug(
                "Agent '%s' subscribed to event type: %s",
                self.name,
                event_type.value
            )

    def subscribe_all(self) -> None:
        """Subscribe to all event types."""
        logger.debug("Agent '%s' subscribed to all events", self.name)
        # Mark with a special indicator
        self._subscribed_events.add(None)  # None indicates all events

    async def _subscribe_to_events(self) -> None:
        """Subscribe agent to configured event types on the event bus."""
        if not self._event_queue:
            return

        if None in self._subscribed_events:
            # Subscribe to all events
            await self.event_bus.subscribe_all(self._event_queue)
            logger.debug("Agent '%s' subscribed to all events on event bus", self.name)
        else:
            # Subscribe to specific event types
            for event_type in self._subscribed_events:
                await self.event_bus.subscribe(event_type, self._event_queue)
                logger.debug(
                    "Agent '%s' subscribed to %s on event bus",
                    self.name,
                    event_type.value
                )

    async def _unsubscribe_from_events(self) -> None:
        """Unsubscribe agent from all events on the event bus."""
        if not self._event_queue:
            return

        await self.event_bus.unsubscribe_all(self._event_queue)
        logger.debug("Agent '%s' unsubscribed from all events", self.name)

    async def _process_events(self) -> None:
        """Process events from the event queue.

        This internal method runs in a loop, waiting for events from the queue
        and calling handle_event for each received event.
        """
        logger.debug("Agent '%s' event processing loop started", self.name)

        while self._running:
            try:
                # Wait for event with timeout to allow checking _running flag
                event = await asyncio.wait_for(
                    self._event_queue.get(),
                    timeout=1.0
                )

                # Handle the event
                try:
                    await self.handle_event(event)
                except Exception as e:
                    logger.error(
                        "Agent '%s' error handling event %s: %s",
                        self.name,
                        event.event_type.value,
                        str(e),
                        exc_info=True
                    )

            except asyncio.TimeoutError:
                # Timeout is normal, just continue
                continue
            except asyncio.CancelledError:
                # Task cancelled, exit loop
                logger.debug("Agent '%s' event processing cancelled", self.name)
                break
            except Exception as e:
                logger.error(
                    "Agent '%s' error in event processing loop: %s",
                    self.name,
                    str(e),
                    exc_info=True
                )

        logger.debug("Agent '%s' event processing loop stopped", self.name)

    async def publish_event(self, event: BaseEvent) -> None:
        """Publish an event to the event bus.

        Args:
            event: Event to publish
        """
        await self.event_bus.publish(event)
        logger.debug(
            "Agent '%s' published event: %s",
            self.name,
            event.event_type.value
        )

    def is_running(self) -> bool:
        """Check if the agent is currently running.

        Returns:
            True if agent is running, False otherwise
        """
        return self._running

    def __str__(self) -> str:
        """String representation of the agent."""
        status = "running" if self._running else "stopped"
        return f"{self.__class__.__name__}(name='{self.name}', status='{status}')"
