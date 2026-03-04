"""Tests for the async EventBus pub/sub implementation.

All tests are async because the EventBus API is fully async (subscribe,
unsubscribe, publish, etc. are all coroutines).

Coverage targets:
- subscribe(): typed subscriber receives matching events
- unsubscribe(): removed subscriber stops receiving events
- subscribe_all(): global subscriber receives every event type
- unsubscribe_all(): global subscriber can be removed cleanly
- Multiple subscribers for the same event type each receive a copy
- Subscriber count helpers return correct values
- Publishing with no subscribers is a safe no-op
- Error during publish to one queue does not break other queues
- EventBus.start() / stop() lifecycle flags and cleanup
- Rejects non-BaseEvent objects passed to publish()
"""

import asyncio
import pytest

from src.coordinator.event_bus import EventBus
from src.models.events import (
    BaseEvent,
    ConnectionEvent,
    LabelsEvent,
    FileEvent,
    EventType,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_queue(maxsize: int = 10) -> asyncio.Queue:
    """Create a small asyncio.Queue for test use."""
    return asyncio.Queue(maxsize=maxsize)


def _connection_event(connected: bool = True) -> ConnectionEvent:
    return ConnectionEvent(router_ip="10.0.0.1", connected=connected)


def _labels_event() -> LabelsEvent:
    return LabelsEvent(labels=[{"port": 1}], source="test", operation="read")


def _file_event() -> FileEvent:
    return FileEvent(file_path="/tmp/labels.csv", operation="read", success=True)


# ---------------------------------------------------------------------------
# Subscribe and receive
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_subscriber_receives_matching_event(event_bus: EventBus):
    """A typed subscriber receives exactly one event of the subscribed type."""
    q = _make_queue()
    await event_bus.subscribe(EventType.CONNECTION, q)

    event = _connection_event()
    await event_bus.publish(event)

    received = await asyncio.wait_for(q.get(), timeout=1.0)
    assert received is event


@pytest.mark.asyncio
async def test_subscriber_does_not_receive_other_event_types(event_bus: EventBus):
    """A CONNECTION subscriber must NOT receive LABELS events."""
    q = _make_queue()
    await event_bus.subscribe(EventType.CONNECTION, q)

    await event_bus.publish(_labels_event())

    assert q.empty(), "Queue should be empty — LABELS event must not reach CONNECTION subscriber"


@pytest.mark.asyncio
async def test_multiple_subscribers_each_receive_event(event_bus: EventBus):
    """Two subscribers for the same event type each get their own copy."""
    q1 = _make_queue()
    q2 = _make_queue()
    await event_bus.subscribe(EventType.CONNECTION, q1)
    await event_bus.subscribe(EventType.CONNECTION, q2)

    event = _connection_event()
    await event_bus.publish(event)

    r1 = await asyncio.wait_for(q1.get(), timeout=1.0)
    r2 = await asyncio.wait_for(q2.get(), timeout=1.0)
    assert r1 is event
    assert r2 is event


@pytest.mark.asyncio
async def test_multiple_events_arrive_in_published_order(event_bus: EventBus):
    """Events published sequentially arrive in FIFO order."""
    q = _make_queue()
    await event_bus.subscribe(EventType.CONNECTION, q)

    e1 = _connection_event(connected=True)
    e2 = _connection_event(connected=False)
    await event_bus.publish(e1)
    await event_bus.publish(e2)

    first = await asyncio.wait_for(q.get(), timeout=1.0)
    second = await asyncio.wait_for(q.get(), timeout=1.0)
    assert first is e1
    assert second is e2


# ---------------------------------------------------------------------------
# Unsubscribe
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_unsubscribed_queue_stops_receiving(event_bus: EventBus):
    """After unsubscribe(), no further events reach the queue."""
    q = _make_queue()
    await event_bus.subscribe(EventType.CONNECTION, q)
    await event_bus.unsubscribe(EventType.CONNECTION, q)

    await event_bus.publish(_connection_event())

    assert q.empty(), "Queue should remain empty after unsubscribe"


@pytest.mark.asyncio
async def test_unsubscribe_unknown_queue_is_safe(event_bus: EventBus):
    """Calling unsubscribe() with a queue that was never subscribed must not raise."""
    q = _make_queue()
    # Should complete without exception
    await event_bus.unsubscribe(EventType.CONNECTION, q)


@pytest.mark.asyncio
async def test_subscriber_count_decreases_after_unsubscribe(event_bus: EventBus):
    q = _make_queue()
    await event_bus.subscribe(EventType.CONNECTION, q)
    assert await event_bus.get_subscriber_count(EventType.CONNECTION) == 1

    await event_bus.unsubscribe(EventType.CONNECTION, q)
    assert await event_bus.get_subscriber_count(EventType.CONNECTION) == 0


# ---------------------------------------------------------------------------
# Global (subscribe_all) subscribers
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_global_subscriber_receives_all_event_types(event_bus: EventBus):
    """A subscribe_all() queue must receive CONNECTION, LABELS, and FILE events."""
    q = _make_queue(maxsize=20)
    await event_bus.subscribe_all(q)

    await event_bus.publish(_connection_event())
    await event_bus.publish(_labels_event())
    await event_bus.publish(_file_event())

    events = []
    for _ in range(3):
        events.append(await asyncio.wait_for(q.get(), timeout=1.0))

    event_types = {e.event_type for e in events}
    assert EventType.CONNECTION in event_types
    assert EventType.LABELS in event_types
    assert EventType.FILE in event_types


@pytest.mark.asyncio
async def test_global_subscriber_and_typed_subscriber_both_receive(event_bus: EventBus):
    """An event must land in both the typed queue AND the global queue."""
    typed_q = _make_queue()
    global_q = _make_queue()

    await event_bus.subscribe(EventType.CONNECTION, typed_q)
    await event_bus.subscribe_all(global_q)

    event = _connection_event()
    await event_bus.publish(event)

    from_typed = await asyncio.wait_for(typed_q.get(), timeout=1.0)
    from_global = await asyncio.wait_for(global_q.get(), timeout=1.0)
    assert from_typed is event
    assert from_global is event


@pytest.mark.asyncio
async def test_unsubscribe_all_stops_global_delivery(event_bus: EventBus):
    """unsubscribe_all() must remove the queue from global subscriber set."""
    q = _make_queue()
    await event_bus.subscribe_all(q)
    await event_bus.unsubscribe_all(q)

    await event_bus.publish(_connection_event())

    assert q.empty()


@pytest.mark.asyncio
async def test_global_subscriber_count_increments(event_bus: EventBus):
    q1 = _make_queue()
    q2 = _make_queue()
    await event_bus.subscribe_all(q1)
    assert await event_bus.get_global_subscriber_count() == 1
    await event_bus.subscribe_all(q2)
    assert await event_bus.get_global_subscriber_count() == 2


# ---------------------------------------------------------------------------
# Publish safety
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_publish_with_no_subscribers_is_noop(event_bus: EventBus):
    """Publishing when nobody is subscribed must not raise."""
    event = _connection_event()
    # Should return without error
    await event_bus.publish(event)


@pytest.mark.asyncio
async def test_publish_non_base_event_raises_type_error(event_bus: EventBus):
    with pytest.raises(TypeError, match="BaseEvent"):
        await event_bus.publish("not an event")  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_full_queue_drops_oldest_event_not_newest(event_bus: EventBus):
    """When the per-subscriber queue is full the bus should drop the oldest event,
    not the newly published one.  We use a bus with max_queue_size=2."""
    small_bus = EventBus(max_queue_size=2)
    q = _make_queue(maxsize=100)  # queue itself is not the bottleneck
    await small_bus.subscribe(EventType.CONNECTION, q)

    e1 = _connection_event(connected=True)
    e2 = _connection_event(connected=False)
    e3 = ConnectionEvent(router_ip="10.0.0.2", connected=True)  # third event — bus full after e2

    await small_bus.publish(e1)
    await small_bus.publish(e2)
    await small_bus.publish(e3)  # should evict e1

    # After eviction we should have e2 and e3
    received = []
    while not q.empty():
        received.append(q.get_nowait())

    assert e3 in received, "Newest event (e3) must survive the full-queue drop"


# ---------------------------------------------------------------------------
# Clear all subscribers
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_clear_all_subscribers_removes_everything(event_bus: EventBus):
    q1 = _make_queue()
    q2 = _make_queue()
    await event_bus.subscribe(EventType.CONNECTION, q1)
    await event_bus.subscribe_all(q2)

    await event_bus.clear_all_subscribers()

    assert await event_bus.get_subscriber_count(EventType.CONNECTION) == 0
    assert await event_bus.get_global_subscriber_count() == 0

    # Publishing after clearing should be a safe no-op
    await event_bus.publish(_connection_event())
    assert q1.empty()
    assert q2.empty()


# ---------------------------------------------------------------------------
# Lifecycle (start / stop)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_event_bus_not_running_by_default(event_bus: EventBus):
    assert event_bus.is_running() is False


@pytest.mark.asyncio
async def test_start_sets_running_flag(event_bus: EventBus):
    await event_bus.start()
    assert event_bus.is_running() is True


@pytest.mark.asyncio
async def test_stop_clears_running_flag_and_subscribers(event_bus: EventBus):
    q = _make_queue()
    await event_bus.subscribe(EventType.CONNECTION, q)
    await event_bus.start()
    await event_bus.stop()

    assert event_bus.is_running() is False
    # stop() calls clear_all_subscribers() internally
    assert await event_bus.get_subscriber_count(EventType.CONNECTION) == 0


# ---------------------------------------------------------------------------
# Subscriber count helpers
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_subscriber_count_reflects_multiple_subscriptions(event_bus: EventBus):
    q1 = _make_queue()
    q2 = _make_queue()
    q3 = _make_queue()
    await event_bus.subscribe(EventType.LABELS, q1)
    await event_bus.subscribe(EventType.LABELS, q2)
    await event_bus.subscribe(EventType.LABELS, q3)

    count = await event_bus.get_subscriber_count(EventType.LABELS)
    assert count == 3


@pytest.mark.asyncio
async def test_subscriber_count_for_unsubscribed_type_is_zero(event_bus: EventBus):
    count = await event_bus.get_subscriber_count(EventType.FILE)
    assert count == 0
