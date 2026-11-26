# Writing a `GroupTransport` for a real Telegram client

TeleBase's Registry mode needs exactly four things from a Telegram user
client (MTProto): join a group, leave it, search its history, and post to
it. This guide describes how to provide them with a TDLib-style client.
It is a **conformance guide, not a drop-in implementation** — every
Telegram client library names these operations differently, and shipping
plausible-looking but untested MTProto code would be worse than shipping
none. The original TeleBase registry runs inside a Telegram iOS fork
built on TDLib's predecessor stack, and its transport is roughly 80 lines
following exactly the mapping below.

## The mapping

| GroupTransport        | TDLib-style equivalent                                             |
| --------------------- | ------------------------------------------------------------------ |
| `currentUserId`       | `getMe` → `id`                                                     |
| `join()`              | `joinChatByUsername` / `joinChat` on the registry supergroup       |
| `leave()`             | `leaveChat`                                                        |
| `search(query:)`      | `searchChatMessages` with the query string, paging until exhausted |
| `post(text:)`         | `sendMessage` with an `inputMessageText`                           |
| `postHeader(_:)`      | `sendMessage` with `inputMessagePhoto` + caption = header (optional override) |

## Rules a conformance must follow

1. **Poster ids come from the client, never from text.** When converting
   a TDLib `message` to `TBTransportMessage`, take `posterId` from
   `message.sender_id` (the `messageSenderUser` case). A message whose
   sender is a chat/channel rather than a user cannot own records —
   either skip it or map it to an id that will never match an owner.

2. **Search returns chronological order.** `searchChatMessages` walks
   newest-first; collect all pages and reverse before returning.
   `TBCodec.assemble` relies on a publication's header message preceding
   its chunks.

3. **Join → operate → leave.** TeleBase calls `join()` before every
   operation batch and `leave()` afterwards. Telegram returns nothing for
   searches in groups you are not a member of, so a conformance must not
   "optimize away" the join. If the account is already a member, joining
   again is a no-op — treat that result as success.

4. **History must be visible.** The registry group should be created with
   visible message history for members; otherwise a freshly joined client
   sees nothing and every read looks empty.

5. **Respect flood limits.** Telegram rate-limits joins, searches and
   posts, especially from young accounts. Surface those errors to the
   caller instead of retrying in a tight loop; TeleBase's 24h cache
   already absorbs most read traffic.

6. **Publishing a photo header.** In the original design the header rides
   as the caption of the record's photo (e.g. a profile banner): caption
   limit 1024 characters, and the header is far below that. If your client
   cannot post photos, the protocol's default `postHeader` (a plain text
   message) is fully valid — readers treat both forms identically.

## Checklist

- [ ] `currentUserId` from the client's own account, not from input.
- [ ] `search` pages through the full result set and returns oldest-first.
- [ ] Sender mapping uses `sender_id`, user senders only.
- [ ] Join/leave are idempotent and leave runs even after a failed search.
- [ ] Errors (including `FLOOD_WAIT`) propagate as thrown errors.
