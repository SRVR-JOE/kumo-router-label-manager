"""Event bus implementation for inter-agent communication.

This module provides an async publish/subscribe event bus for coordinating
communication between agents in the KUMO router management system.
"""

import asyncio
from typing import Callable, Dict, List, Set, Awaitable
from collections import defaultdict
import logging
# Removed threading.Lock - using asyncio.Lock for async-safe locking

from ..models.events import BaseEvent, EventType

logger = logging.getLogger(__name__)


class EventBus:
    """Async event bus for publish/subscribe communication between agents.

    The event bus allows agents to publish events and subscribe to specific
    event types. It uses asyncio queues for thread-safe event delivery and
    supports multiple subscribers per event type.
    """

    def __init__(self, max_queue_size: int = 1000) -> None:
        """Initialize the event bus.

        Args:
            max_queue_size: Maximum number of events to queue per subscriber
        """
        self._subscribers: Dict[EventType, Set[asyncio.Queue]] = defaultdict(set)
        self._global_subscribers: Set[asyncio.Queue] = set()
        self._max_queue_size = max_queue_size
        self._lock = asyncio.Lock()
        self._running = False

        logger.info("EventBus initialized with max queue size: %d", max_queue_size)

    async def subscribe(
        self,
        event_type: EventType,
        queue: asyncio.Queue,
    ) -> None:
        """Subscribe to a specific event type.

        Args:
            event_type: Type of events to subscribe to
            queue: Asyncio queue to receive events
        """
        async with self._lock:
            self._subscribers[event_type].add(queue)
            logger.debug(
                "Subscriber added for event type: %s (total: %d)",
                event_type.value,
                len(self._subscribers[event_type])
            )

    async def subscribe_all(self, queue: asyncio.Queue) -> None:
        """Subscribe to all event types.

        Args:
            queue: Asyncio queue to receive all events
        """
        async with self._lock:
            self._global_subscribers.add(queue)
            logger.debug(
                "Global subscriber added (total: %d)",
                len(self._global_subscribers)
            )

    async def unsubscribe(
        self,
        event_type: EventType,
        queue: asyncio.Queue,
    ) -> None:
        """Unsubscribe from a specific event type.

        Args:
            event_type: Type of events to unsubscribe from
            queue: Queue to remove from subscribers
        """
        async with self._lock:
            if queue in self._subscribers[event_type]:
                self._subscribers[event_type].remove(queue)
                logger.debug(
                    "Subscriber removed from event type: %s (remaining: %d)",
                    event_type.value,
                    len(self._subscribers[event_type])
                )

    def unsubscribe_all(self, queue: asyncio.Queue) -> None:
        """Unsubscribe from all event types.

        Args:
            queue: Queue to remove from all subscriptions
        """
        with self._lock:
            # Remove from global subscribers
            if queue in self._global_subscribers:
                self._global_subscribers.remove(queue)
                logger.debug(
                    "Global subscriber removed (remaining: %d)",
                    len(self._global_subscribers)
                )

            # Remove from specific event type subscribers
            for event_type in list(self._subscribers.keys()):
                if queue in self._subscribers[event_type]:
                    self._subscribers[event_type].remove(queue)
                    logger.debug(
                        "Subscriber removed from event type: %s",
                        event_type.value
                    )

    async def publish(self, event: BaseEvent) -> None:
        """Publish an event to all subscribers.

        Args:
            event: Event to publish
        """
        if not isinstance(event, BaseEvent):
            raise TypeError(f"Event must be a BaseEvent instance, got {type(event)}")

        logger.debug(
            "Publishing event: %s at %s",
            event.event_type.value,
            event.timestamp.isoformat()
        )

        # Get subscribers for this event type
        with self._lock:
            specific_subscribers = self._subscribers[event.event_type].copy()
            global_subscribers = self._global_subscribers.copy()

        all_subscribers = specific_subscribers | global_subscribers

        if not all_subscribers:
            logger.debug(
                "No subscribers for event type: %s",
                event.event_type.value
            )
            return

        # Publish to all subscribers
        tasks = []
        for queue in all_subscribers:
            tasks.append(self._publish_to_queue(queue, event))

        # Wait for all publishes to complete
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Log any errors
        error_count = sum(1 for r in results if isinstance(r, Exception))
        if error_count > 0:
            logger.warning(
                "Failed to publish to %d/%d subscribers",
                error_count,
                len(all_subscribers)
            )

    async def _publish_to_queue(self, queue: asyncio.Queue, event: BaseEvent) -> None:
        """Publish event to a single queue with error handling.

        Args:
            queue: Queue to publish to
            event: Event to publish
        """
        try:
            # Use put_nowait to avoid blocking if queue is full
            if queue.qsize() >= self._max_queue_size:
                logger.warning(
                    "Queue full (size: %d), dropping oldest event",
                    queue.qsize()
                )
                # Remove oldest event
                try:
                    queue.get_nowait()
                except asyncio.QueueEmpty:
                    pass

            await queue.put(event)
        except Exception as e:
            logger.error(
                "Failed to publish event to queue: %s",
                str(e),
                exc_info=True
            )

    def get_subscriber_count(self, event_type: EventType) -> int:
        """Get number of subscribers for a specific event type.

        Args:
            event_type: Event type to check

        Returns:
            Number of subscribers
        """
        with self._lock:
            return len(self._subscribers[event_type])

    def get_global_subscriber_count(self) -> int:
        """Get number of global subscribers.

        Returns:
            Number of global subscribers
        """
        with self._lock:
            return len(self._global_subscribers)

    def clear_all_subscribers(self) -> None:
        """Clear all subscribers from the event bus."""
        with self._lock:
            self._subscribers.clear()
            self._global_subscribers.clear()
            logger.info("All subscribers cleared from event bus")

    async def start(self) -> None:
        """Start the event bus."""
        self._running = True
        logger.info("EventBus started")

    async def stop(self) -> None:
        """Stop the event bus and clear all subscribers."""
        self._running = False
        self.clear_all_subscribers()
        logger.info("EventBus stopped")

    def is_running(self) -> bool:
        """Check if the event bus is running.

        Returns:
            True if running, False otherwise
        """
        return self._running
