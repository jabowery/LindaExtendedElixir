# Linda

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `linda` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:linda, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/linda>.

# What follows should be considered an abstract spec
Abstract Implementation Spec should be considered a *roadmap*

```
# Extended Linda Coordination Language Specification

## 1. Tuple Space Model
- **Globally shared, unordered multiset** of tuples.
- Tuples are of the form `("tag", value1, ..., valuen)`.
- Operations: `out(t)` (add), `in(t)` (remove), `rd(t)` (read), extended with collective variants.

---

## 2. Collective Primitives
### Conditions
| Condition              | Logical Meaning                          |
|------------------------|------------------------------------------|
| `ALL_PRESENT`          | All tuples in set `S` exist in the TS.   |
| `NOT_ALL_PRESENT`      | At least one tuple in `S` is absent.     |
| `ALL_ABSENT`           | No tuple in `S` exists in the TS.        |
| `NOT_ALL_ABSENT`       | At least one tuple in `S` is present.    |

### Blocking Operations
| Operation               | Behavior                                                                 |
|-------------------------|--------------------------------------------------------------------------|
| `coll_in(S, condition)` | Blocks until `condition` is met. Removes tuples if `ALL_PRESENT`/`NOT_ALL_ABSENT`. |
| `coll_rd(S, condition)` | Blocks until `condition` is met. Returns matching tuples.               |
| `coll_await(S, condition)` | Blocks until absence-related conditions (`ALL_ABSENT`/`NOT_ALL_PRESENT`) are met. |

### Non-Blocking Operations
| Operation               | Behavior                                                                 |
|-------------------------|--------------------------------------------------------------------------|
| `coll_inp(S, condition)` | Non-blocking `coll_in`. Returns `true` + removes tuples if successful.  |
| `coll_rdp(S, condition)` | Non-blocking `coll_rd`. Returns `true` + matching tuples if successful. |
| `coll_awaitp(S, condition)` | Non-blocking `coll_await`. Returns `true` if condition met.          |

---

## 3. Operational Semantics
### `coll_in(S, ALL_PRESENT)`
- **Precondition**: \( \forall t \in S, t \in TS \)
- **Postcondition**: \( TS' = TS \setminus S \)
- **Atomicity**: Check and removal occur atomically.

### `coll_await(S, ALL_ABSENT)`
- **Precondition**: \( \forall t \in S, t \notin TS \)
- **Postcondition**: \( TS' = TS \)

---

## 4. Examples
### Barrier Synchronization
```python
# Workers signal completion; coordinator waits for all:
out("done", worker_id)
coll_in([("done", 1), ("done", 2)], ALL_PRESENT)
```

### Resource Pool
```python
# Claim a free resource if available:
coll_rd([("resource", "free", *)], NOT_ALL_ABSENT)
```

---

# Abstract Implementation Specification

## 1. Core Components
- **Tuple Space (TS)**: Multiset storing tuples.
- **Scheduler**: Manages dependencies and triggers blocked workers.
- **Dependency Structures**:
  - **Tuple Subscription Map**: Tracks which operations depend on specific tuple events.
  - **Pending Operations Table**: Stores metadata for pending operations (e.g., conditions, tuple sets).

---

## 2. Dependency Structures
### Tuple Subscription Map
```python
{
  "template": ("tag", *),
  "subscriptions": [
    (op_id, "add" | "remove")
  ]
}
```
- Maps tuple templates to operations waiting for their addition/removal.

### Pending Operations Table
```python
{
  "op_id": {
    "condition": "ALL_PRESENT",
    "set_S": [("tag1", val), ("tag2", *)],
    "status": {"t1": True, "t2": False},
    "action": "remove_tuples"
  }
}
```

---

## 3. Scheduler Workflow
### Event-Driven Workflow
1. **Operation Submission**:
   - If condition is immediately satisfied, execute action.
   - Else, subscribe to relevant tuple events and track in the Pending Operations Table.

2. **Tuple Event Handling**:
   - On `out(t)` or `in(t)`:
     - Update `status` for all operations subscribed to `t`.
     - Re-evaluate conditions for affected operations.
     - Trigger actions and unsubscribe satisfied operations.

### Atomicity Guarantees
- Tuple state checks and modifications are atomic.
- Event processing is serialized to prevent races.

---

## 4. Subscription Logic
| Condition              | Subscriptions                           |
|------------------------|-----------------------------------------|
| `ALL_PRESENT`          | "add" for missing tuples in `S`.        |
| `ALL_ABSENT`           | "remove" for existing tuples in `S`.    |
| `NOT_ALL_PRESENT`      | "remove" for all tuples in `S`.         |
| `NOT_ALL_ABSENT`       | "add" for all tuples in `S`.            |

---

## 5. Advantages
- **No Polling**: Workers block until dependencies resolve.
- **Efficiency**: Conditions re-evaluated only on relevant tuple changes.
- **Scalability**: Subscriptions limit checks to affected operations.

---

## 6. Formal State Transitions
### Transition Rules
- **Add Tuple `t`**:
  - Update TS: \( TS' = TS \cup \{t\} \)
  - Notify operations subscribed to `t`'s "add" event.

- **Remove Tuple `t`**:
  - Update TS: \( TS' = TS \setminus \{t\} \)
  - Notify operations subscribed to `t`'s "remove" event.
```
