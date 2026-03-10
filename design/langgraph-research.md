# LangGraph Technical Research

**Date:** 2026-03-10
**Context:** Gerbil AI Suite — background research for LangGraph-based orchestration
**Source:** Official LangGraph Python documentation (latest, v0.x–1.x)

---

## Table of Contents

1. [Core Concepts](#1-core-concepts)
2. [Two APIs: Graph API vs Functional API](#2-two-apis-graph-api-vs-functional-api)
3. [State Management](#3-state-management)
4. [Persistence & Checkpointing](#4-persistence--checkpointing)
5. [Human-in-the-Loop (Interrupts)](#5-human-in-the-loop-interrupts)
6. [Subgraphs & Composition](#6-subgraphs--composition)
7. [Tool Integration](#7-tool-integration)
8. [Streaming](#8-streaming)
9. [Memory (Short-term & Long-term)](#9-memory-short-term--long-term)
10. [Error Handling & Retry](#10-error-handling--retry)
11. [Deployment & Application Structure](#11-deployment--application-structure)
12. [Best Practices & Recommendations](#12-best-practices--recommendations)
13. [Relevance to Gerbil AI Suite](#13-relevance-to-gerbil-ai-suite)

---

## 1. Core Concepts

LangGraph is a **low-level orchestration framework** for building stateful, long-running AI agent applications. It models workflows as **directed graphs** where:

- **Nodes** are Python functions (sync or async) that receive state and return state updates
- **Edges** define the flow between nodes (static or conditional)
- **State** is a shared `TypedDict` that flows through the graph and is automatically persisted

Key differentiators from plain LangChain:
- **Durable execution** — state is checkpointed after every node, enabling crash recovery
- **Human-in-the-loop** — first-class `interrupt()` primitive to pause and resume
- **Streaming** — built-in support for streaming node outputs, messages, and custom data
- **Cycles** — supports loops and recursive patterns (unlike DAG-only frameworks)

### Minimal Example

```python
from langgraph.graph import StateGraph, START, END
from typing_extensions import TypedDict

class State(TypedDict):
    input: str
    output: str

def process(state: State):
    return {"output": state["input"].upper()}

graph = StateGraph(State)
graph.add_node("process", process)
graph.add_edge(START, "process")
graph.add_edge("process", END)
app = graph.compile()

result = app.invoke({"input": "hello"})
# {"input": "hello", "output": "HELLO"}
```

---

## 2. Two APIs: Graph API vs Functional API

LangGraph offers two complementary APIs. They can be **mixed and matched**.

### 2.1 Graph API (StateGraph)

Best for:
- **Complex multi-agent coordination** with clear visualization
- Workflows requiring **explicit control flow** (conditional edges, parallel branches)
- Systems needing **independent subgraph memory**
- When the **graph structure itself is the documentation**

```python
from langgraph.graph import StateGraph, START, END

class AgentState(TypedDict):
    messages: list
    current_tool: str
    retry_count: int

def should_continue(state):
    if state["retry_count"] > 3:
        return "end"
    elif state["current_tool"] == "search":
        return "process_search"
    else:
        return "call_llm"

workflow = StateGraph(AgentState)
workflow.add_node("call_llm", call_llm_node)
workflow.add_node("process_search", search_node)
workflow.add_conditional_edges("call_llm", should_continue)
app = workflow.compile(checkpointer=checkpointer)
```

### 2.2 Functional API (`@entrypoint` + `@task`)

Best for:
- **Rapid prototyping** and simple linear or branching workflows
- When you want **standard Python control flow** (if/else, while loops)
- **Function-scoped state** (no global TypedDict needed)
- Wrapping existing functions with minimal changes

```python
from langgraph.func import entrypoint, task

@task
def process_step(data: str) -> dict:
    return {"processed": data.lower().strip()}

@entrypoint(checkpointer=checkpointer)
def workflow(user_input: str) -> str:
    processed = process_step(user_input).result()
    if "urgent" in processed["processed"]:
        return handle_urgent(processed).result()
    return handle_normal(processed).result()
```

### 2.3 Combining Both APIs

You can call Graph API graphs from Functional API entrypoints and vice versa:

```python
@entrypoint()
def some_workflow(some_input: dict) -> int:
    result_1 = some_graph.invoke(...)       # Graph API graph
    result_2 = another_graph.invoke(...)    # Another Graph API graph
    return {"result_1": result_1, "result_2": result_2}
```

### 2.4 Decision Guide

| Criterion | Graph API | Functional API |
|---|---|---|
| Clear visualization of flow | ✅ Excellent (Mermaid export) | ❌ Implicit |
| Parallel node execution | ✅ Built-in via fan-out edges | ⚠️ Manual with futures |
| Complex conditional routing | ✅ `add_conditional_edges` | ✅ Plain Python if/else |
| Subgraph composition | ✅ First-class | ⚠️ Via `.invoke()` |
| Human-in-the-loop | ✅ `interrupt()` | ✅ `interrupt()` |
| Rapid prototyping | ⚠️ More boilerplate | ✅ Minimal |
| State management | Global TypedDict | Function-scoped |

---

## 3. State Management

### 3.1 State as TypedDict

State is defined via Python's `TypedDict`. Every node receives the full state and returns a **partial update** (only the fields it changes):

```python
from typing_extensions import TypedDict

class State(TypedDict):
    foo: int
    bar: list[str]

def my_node(state: State):
    # Only return what changed — other fields are preserved
    return {"foo": state["foo"] + 1}
```

### 3.2 Reducers

By default, returned values **overwrite** existing state. For **append-style** semantics (e.g., accumulating lists, messages), use `Annotated` with a reducer:

```python
from typing import Annotated
from operator import add

class State(TypedDict):
    foo: int                            # Default: overwrite
    bar: Annotated[list[str], add]      # Reducer: list concatenation
```

**Built-in `add_messages` reducer** — essential for chat applications:

```python
from langgraph.graph.message import add_messages
from langchain_core.messages import AnyMessage

class GraphState(TypedDict):
    messages: Annotated[list[AnyMessage], add_messages]
```

The `add_messages` reducer handles:
- Appending new messages
- Deduplicating by message ID
- Replacing messages by ID (for tool message updates)

### 3.3 MessagesState Shorthand

For the common pattern of a state with just `messages`:

```python
from langgraph.graph import MessagesState

# Equivalent to:
# class MessagesState(TypedDict):
#     messages: Annotated[list[AnyMessage], add_messages]
```

### 3.4 RemainingSteps (Managed State)

LangGraph provides `RemainingSteps` to access the number of steps remaining before hitting the recursion limit:

```python
from langgraph.managed.is_last_step import RemainingSteps

class State(TypedDict):
    aggregate: Annotated[list, operator.add]
    remaining_steps: RemainingSteps  # Automatically injected

def my_node(state: State):
    if state["remaining_steps"] <= 2:
        return {"aggregate": ["stopping_early"]}
    return {"aggregate": ["continue"]}
```

---

## 4. Persistence & Checkpointing

LangGraph automatically persists state after every node execution via **checkpointers**. This enables:
- **Crash recovery** — resume from the last completed node
- **Human-in-the-loop** — pause at interrupt, resume later
- **Time travel** — replay from any checkpoint
- **Multi-turn conversations** — state persists across invocations

### 4.1 Available Checkpointers

| Checkpointer | Package | Use Case |
|---|---|---|
| `InMemorySaver` | `langgraph` | Development/testing |
| `SqliteSaver` | `langgraph` | Local persistence |
| `PostgresSaver` | `langgraph-checkpoint-postgres` | **Production** |
| `AsyncPostgresSaver` | `langgraph-checkpoint-postgres` | Production (async) |
| `RedisSaver` | `langgraph-checkpoint-redis` | Production (Redis) |

### 4.2 PostgresSaver (Production)

```python
from langgraph.checkpoint.postgres import PostgresSaver

DB_URI = "postgresql://postgres:postgres@localhost:5442/postgres?sslmode=disable"
with PostgresSaver.from_conn_string(DB_URI) as checkpointer:
    graph = builder.compile(checkpointer=checkpointer)
```

**Async variant:**

```python
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver

async with AsyncPostgresSaver.from_conn_string(DB_URI) as checkpointer:
    graph = builder.compile(checkpointer=checkpointer)
```

### 4.3 Thread IDs

Every invocation requires a `thread_id` — this is the primary key for checkpoint storage:

```python
config = {"configurable": {"thread_id": "user-session-123"}}
result = graph.invoke(input_data, config=config)
```

### 4.4 State Inspection & Time Travel

```python
# Get latest state
state = graph.get_state({"configurable": {"thread_id": "1"}})

# Get specific checkpoint
state = graph.get_state({
    "configurable": {
        "thread_id": "1",
        "checkpoint_id": "0c62ca34-ac19-445d-bbb0-5b4984975b2a"
    }
})

# Replay from a checkpoint
graph.invoke(None, config={
    "configurable": {
        "thread_id": "1",
        "checkpoint_id": "0c62ca34-..."
    }
})

# Update state manually
graph.update_state(config, {"foo": 2, "bar": ["b"]})
```

### 4.5 Encrypted Persistence

For sensitive data:

```python
from langgraph.checkpoint.serde.encrypted import EncryptedSerializer
from langgraph.checkpoint.postgres import PostgresSaver

serde = EncryptedSerializer.from_pycryptodome_aes()  # reads LANGGRAPH_AES_KEY env var
checkpointer = PostgresSaver.from_conn_string("postgresql://...", serde=serde)
```

---

## 5. Human-in-the-Loop (Interrupts)

LangGraph's `interrupt()` function is the **primary mechanism** for pausing graph execution to wait for human input. This is critical for Gerbil's approval gates.

### 5.1 The `interrupt()` Function

```python
from langgraph.types import interrupt

def approval_node(state: State):
    # Pause execution — payload is returned to caller as __interrupt__
    approved = interrupt({
        "question": "Do you approve this action?",
        "details": state["action_details"]
    })
    # Execution resumes here when Command(resume=...) is sent
    return {"approved": approved}
```

**Requirements:**
- A checkpointer must be configured
- A `thread_id` must be provided
- Payload must be **JSON-serializable**

### 5.2 Resuming After Interrupt

```python
# Initial invocation hits interrupt
config = {"configurable": {"thread_id": "approval-123"}}
initial = graph.invoke({"action_details": "Transfer $500"}, config=config)
print(initial["__interrupt__"])  # Shows the interrupt payload

# Resume with approval
from langgraph.types import Command
resumed = graph.invoke(Command(resume=True), config=config)
```

### 5.3 Approval Pattern with Command Routing

```python
from langgraph.types import Command, interrupt
from typing import Literal

def approval_node(state: State) -> Command[Literal["proceed", "cancel"]]:
    is_approved = interrupt({
        "question": "Do you want to proceed?",
        "details": state["action_details"]
    })
    if is_approved:
        return Command(goto="proceed")
    else:
        return Command(goto="cancel")
```

### 5.4 Tool Call Review Pattern

For reviewing individual tool calls before execution — directly applicable to Gerbil's per-tool-call approval:

```python
@tool(name="run_query", description="Run a SQL query")
def run_query_with_review(config: RunnableConfig, **tool_input):
    response = interrupt([{
        "action": "run_query",
        "args": tool_input,
        "description": "Please review the tool call"
    }])

    if response["type"] == "accept":
        return run_query.invoke(tool_input, config)
    elif response["type"] == "edit":
        return run_query.invoke(response["args"]["args"], config)
    elif response["type"] == "response":
        return response["args"]  # User feedback instead of tool execution
```

### 5.5 Compile-Time Interrupts (Static Breakpoints)

For always interrupting before/after specific nodes:

```python
graph = builder.compile(
    interrupt_before=["sensitive_node"],
    interrupt_after=["review_node"],
    checkpointer=checkpointer,
)
```

### 5.6 Best Practices for Interrupts

- **Always pass JSON-serializable data** to `interrupt()` — strings, numbers, bools, dicts with simple values
- **Never pass non-serializable objects** (Pydantic models, dataclasses, etc.) directly
- **One `interrupt()` per node execution** is cleanest — multiple interrupts in the same node work but are harder to reason about
- Use `Command(goto=...)` for routing after an interrupt to keep the routing logic in the same node

---

## 6. Subgraphs & Composition

### 6.1 Adding a Compiled Graph as a Node

The simplest approach — add a compiled subgraph directly:

```python
subgraph = subgraph_builder.compile()

builder = StateGraph(State)
builder.add_node("subgraph", subgraph)   # Compiled graph as a node
builder.add_edge(START, "subgraph")
```

**Requirement:** Parent and subgraph must share **at least some state keys** for automatic state passing.

### 6.2 Subgraphs with Different State Schemas

When parent and subgraph have different state structures, wrap in a function to transform:

```python
class ParentState(TypedDict):
    foo: str

class SubgraphState(TypedDict):
    bar: str

def call_subgraph(state: ParentState):
    response = subgraph.invoke({"bar": state["foo"]})  # Transform in
    return {"foo": response["bar"]}                     # Transform out

builder = StateGraph(ParentState)
builder.add_node("subgraph_node", call_subgraph)
```

### 6.3 Subgraph with Independent Memory

Subgraphs can have their own checkpointer for independent conversation history:

```python
subgraph = subgraph_builder.compile(checkpointer=True)
# True = inherit parent's checkpointer type but maintain separate state
```

### 6.4 Cross-Graph Navigation with Command

Navigate from a subgraph node back to the parent:

```python
from langgraph.types import Command

def my_subgraph_node(state) -> Command[Literal["parent_node"]]:
    return Command(
        update={"foo": "bar"},
        goto="parent_node",
        graph=Command.PARENT  # Navigate to parent graph
    )
```

---

## 7. Tool Integration

### 7.1 Defining Tools

Use LangChain's `@tool` decorator:

```python
from langchain.tools import tool

@tool
def search(query: str) -> str:
    """Search the web for information."""
    return do_search(query)

tools = [search]
tools_by_name = {t.name: t for t in tools}
```

### 7.2 Binding Tools to Models

```python
from langchain.chat_models import init_chat_model

model = init_chat_model("claude-sonnet-4-5-20250929", temperature=0)
model_with_tools = model.bind_tools(tools)
```

### 7.3 ToolNode (Prebuilt)

`ToolNode` automatically executes tool calls from an `AIMessage`:

```python
from langgraph.prebuilt import ToolNode, tools_condition

tool_node = ToolNode(
    tools=[search, calculator],
    handle_tool_errors=True,   # Return error as ToolMessage instead of raising
    messages_key="messages"
)

# In graph:
workflow.add_node("tools", tool_node)
workflow.add_conditional_edges("agent", tools_condition, {
    "tools": "tools",
    END: END,
})
```

### 7.4 Manual Tool Execution

For more control (e.g., approval gates per tool call):

```python
@task
def call_tool(tool_call: ToolCall):
    tool = tools_by_name[tool_call["name"]]
    return tool.invoke(tool_call)

@entrypoint()
def agent(messages: list[BaseMessage]):
    response = call_llm(messages).result()
    while response.tool_calls:
        tool_results = [call_tool(tc).result() for tc in response.tool_calls]
        messages = add_messages(messages, [response, *tool_results])
        response = call_llm(messages).result()
    return add_messages(messages, response)
```

### 7.5 create_react_agent (Prebuilt)

For quick ReAct-style agents:

```python
from langgraph.prebuilt import create_react_agent

agent = create_react_agent(
    model=model,
    tools=tools,
    prompt="You are a helpful assistant.",
    checkpointer=checkpointer
)

result = agent.invoke(
    {"messages": [{"role": "user", "content": "What's the weather?"}]},
    config={"configurable": {"thread_id": "123"}}
)
```

### 7.6 InjectedState for Tools

Tools can access the full graph state:

```python
from langgraph.prebuilt import InjectedState

@tool
def get_context(query: str, state: Annotated[dict, InjectedState]) -> str:
    """Tool that can read graph state."""
    msg_count = len(state.get("messages", []))
    return f"Found {msg_count} messages in context"
```

---

## 8. Streaming

### 8.1 Stream Modes

```python
# Stream state values after each node
for chunk in graph.stream(input, config, stream_mode="values"):
    print(chunk)

# Stream node updates (deltas)
for chunk in graph.stream(input, config, stream_mode="updates"):
    print(chunk)

# Stream multiple modes simultaneously
async for metadata, mode, chunk in graph.astream(
    input, stream_mode=["messages", "updates"], config=config
):
    if mode == "messages":
        msg, _ = chunk
        # Handle streaming message tokens
    elif mode == "updates":
        if "__interrupt__" in chunk:
            # Handle interrupt
            pass
```

### 8.2 Custom Streaming with StreamWriter

```python
from langgraph.config import get_stream_writer

@entrypoint(checkpointer=checkpointer)
def main(inputs: dict) -> int:
    writer = get_stream_writer()
    writer("Started processing")
    result = inputs["x"] * 2
    writer(f"Result is {result}")
    return result

for mode, chunk in main.stream({"x": 5}, stream_mode=["custom", "updates"], config=config):
    print(f"{mode}: {chunk}")
```

---

## 9. Memory (Short-term & Long-term)

### 9.1 Short-term Memory (Checkpointer)

The checkpointer provides **within-thread** memory:

```python
# First invocation
graph.invoke({"messages": [{"role": "user", "content": "I'm Bob"}]}, config)
# Second invocation — same thread_id, so the model remembers Bob
graph.invoke({"messages": [{"role": "user", "content": "What's my name?"}]}, config)
```

### 9.2 Long-term Memory (Store)

For **cross-thread** memory (user preferences, facts learned over time):

```python
from langgraph.store.postgres import PostgresStore  # Production
from langgraph.store.memory import InMemoryStore     # Development

store = PostgresStore.from_conn_string(DB_URI)
graph = builder.compile(checkpointer=checkpointer, store=store)
```

**Storing and retrieving memories via Runtime:**

```python
from langgraph.runtime import Runtime
from dataclasses import dataclass

@dataclass
class Context:
    user_id: str

async def call_model(state: MessagesState, runtime: Runtime[Context]):
    user_id = runtime.context.user_id
    namespace = (user_id, "memories")

    # Search memories
    memories = await runtime.store.asearch(
        namespace,
        query=state["messages"][-1].content,
        limit=3
    )

    # Store new memory
    await runtime.store.aput(
        namespace,
        str(uuid.uuid4()),
        {"memory": "User prefers Dutch language"}
    )
```

### 9.3 Semantic Search on Memories

```python
from langchain.embeddings import init_embeddings
from langgraph.store.memory import InMemoryStore

embeddings = init_embeddings(model="text-embedding-ada-002")
store = InMemoryStore()
# Store now supports semantic search via embeddings
```

---

## 10. Error Handling & Retry

### 10.1 Retry Policies

```python
from langgraph.types import RetryPolicy

# Default retry policy (retries on most exceptions)
builder.add_node("node_name", node_function, retry_policy=RetryPolicy())

# Custom: retry only on specific errors
builder.add_node(
    "query_db",
    query_database,
    retry_policy=RetryPolicy(retry_on=sqlite3.OperationalError)
)

# Custom: max attempts
builder.add_node("model", call_model, retry_policy=RetryPolicy(max_attempts=5))
```

### 10.2 Recursion Limits

```python
from langgraph.errors import GraphRecursionError

try:
    result = graph.invoke(inputs, {"recursion_limit": 10})
except GraphRecursionError:
    result = {"messages": ["Fallback: recursion limit exceeded"]}
```

### 10.3 Proactive Recursion Handling (RemainingSteps)

```python
from langgraph.managed.is_last_step import RemainingSteps

class State(TypedDict):
    remaining_steps: RemainingSteps

def my_node(state):
    if state["remaining_steps"] <= 2:
        return {"output": "Stopping to avoid recursion limit"}
```

---

## 11. Deployment & Application Structure

### 11.1 Recommended Project Structure

```
my-app/
├── my_agent/
│   ├── utils/
│   │   ├── __init__.py
│   │   ├── tools.py         # Tool definitions
│   │   ├── nodes.py         # Node functions
│   │   └── state.py         # State TypedDict definitions
│   ├── __init__.py
│   └── agent.py             # Graph construction & compilation
├── .env                     # Environment variables
├── langgraph.json           # LangGraph configuration
└── pyproject.toml           # Dependencies
```

### 11.2 langgraph.json Configuration

```json
{
  "dependencies": ["langchain_openai", "./my_agent"],
  "graphs": {
    "my_agent": "./my_agent/agent.py:agent"
  },
  "env": "./.env"
}
```

### 11.3 Local Development Server

```bash
pip install -U "langgraph-cli[inmem]"
langgraph dev                # Start local server
langgraph dev --tunnel       # With secure tunnel
```

### 11.4 LangGraph SDK for Remote Interaction

```python
from langgraph_sdk import get_sync_client

client = get_sync_client(url="http://localhost:8000", api_key="...")
for chunk in client.runs.stream(
    None,
    "my_agent",
    input={"messages": [{"role": "human", "content": "Hello"}]},
    stream_mode="updates",
):
    print(chunk.data)
```

### 11.5 Graph Visualization

```python
# Mermaid syntax
print(graph.get_graph().draw_mermaid())

# PNG image
from IPython.display import Image, display
display(Image(graph.get_graph().draw_mermaid_png()))
```

---

## 12. Best Practices & Recommendations

### 12.1 State Design

1. **Keep state flat** — avoid deeply nested objects. LangGraph's reducers work on top-level keys.
2. **Use reducers for accumulating data** — `Annotated[list, add]` for lists, `add_messages` for message histories.
3. **Return only changed fields** — nodes should return partial state updates, not the full state.
4. **Use TypedDict, not dataclasses** — LangGraph's serialization and checkpointing is optimized for TypedDict.
5. **Make all state JSON-serializable** — especially important for persistence and interrupt payloads.

### 12.2 Graph Design

1. **One responsibility per node** — each node should do one thing well (query, transform, approve).
2. **Use `Command` for combined routing + state updates** — eliminates the need for separate conditional edge functions.
3. **Prefer `interrupt()` over `interrupt_before`/`interrupt_after`** — runtime interrupts are more flexible than compile-time ones.
4. **Use subgraphs for reusable workflows** — e.g., the "approval gate" pattern can be a shared subgraph.
5. **Fan-out with multiple edges from START** for parallel execution — all nodes connected from the same source run in parallel.

### 12.3 API Choice

1. **Use Graph API for the orchestration layer** — it gives clear visualization and explicit parallel execution.
2. **Use Functional API for leaf-level tasks** — simpler syntax for data processing and simple branching.
3. **Combine both** — Graph API for the high-level coordination graph, Functional API `@task` for individual operations.

### 12.4 Persistence

1. **Always use PostgresSaver in production** — InMemorySaver and SqliteSaver are for testing only.
2. **Use `thread_id` = external correlation ID** — e.g., Slack thread timestamp for Gerbil.
3. **Enable encryption** for production checkpoints if handling sensitive data.
4. **Call `checkpointer.setup()`** on first run to create tables.

### 12.5 Human-in-the-Loop

1. **Keep interrupt payloads simple and serializable** — strings, dicts with primitive values.
2. **Design for resumability** — the graph should be able to resume from any interrupt point.
3. **Use session-wide consent patterns** — start with per-call approval, allow "approve all" to skip remaining gates.
4. **Log all approval decisions** in state for audit trail.

### 12.6 Error Handling

1. **Add RetryPolicy to all external I/O nodes** — MCP calls, API calls, database queries.
2. **Set `handle_tool_errors=True` on ToolNode** — returns errors as ToolMessages instead of crashing.
3. **Handle recursion limits proactively** with `RemainingSteps`.
4. **Log data gaps** — if a tool returns an error, record it in state rather than failing the run.

### 12.7 Performance

1. **Use async** (`astream`, `ainvoke`, `AsyncPostgresSaver`) — better throughput for I/O-heavy workloads.
2. **Parallelize independent phases** — fan-out edges let LangGraph run nodes concurrently.
3. **Stream responses** — use `stream_mode=["messages", "updates"]` for real-time feedback.

---

## 13. Relevance to Gerbil AI Suite

### Design Alignment

| Gerbil Design Doc Concept | LangGraph Feature | Status |
|---|---|---|
| `GerbilBaseState` TypedDict | `StateGraph` with TypedDict + reducers | ✅ Fully supported |
| `messages: Annotated[list, add_messages]` | Built-in `add_messages` reducer | ✅ Exact match |
| `PostgresSaver` checkpointer | `langgraph-checkpoint-postgres` | ✅ Production-ready |
| `thread_id` = `slack_thread_ts` | `configurable.thread_id` | ✅ Exact match |
| Per-tool approval gate | `interrupt()` + `Command(resume=...)` | ✅ First-class support |
| Session-wide consent | State flag + conditional `interrupt()` skip | ✅ Standard pattern |
| Shared intake subgraph | Subgraph composition | ✅ Built-in |
| Phase-based research nodes | Sequential nodes with conditional edges | ✅ Straightforward |
| Parallel research phases | Fan-out edges from same source | ✅ Built-in |
| Crash recovery / pod restart | Checkpointing resumes from last node | ✅ Core feature |
| MCP tool integration | `@tool` + `ToolNode` or manual execution | ✅ Via LangChain tools |
| `RetryPolicy` for MCP errors | `RetryPolicy(max_attempts=3)` | ✅ Built-in |
| Audit log (`approval_log`) | State accumulation with `Annotated[list, add]` | ✅ Reducer pattern |
| LLM provider abstraction | `init_chat_model()` / `BaseChatModel` | ✅ LangChain core feature |

### Recommendations for Implementation

1. **Use Graph API for the main orchestration graphs** (intake, release report, incident postmortem) — the explicit graph structure maps 1:1 to the design docs and enables Mermaid visualization for documentation.

2. **Use Functional API for individual research phase logic** — each phase node (e.g., `research_database`) can be a `@task` that does the actual MCP querying and file writing.

3. **Implement the approval gate as a reusable pattern** using `interrupt()`:
   ```python
   def tool_approval_gate(state):
       if state["session_consent"]:
           return  # Skip approval
       decision = interrupt({
           "tool": tool_name,
           "args": tool_args,
           "question": "Approve this tool call?"
       })
       if decision == "approve_all":
           return {"session_consent": True}
       elif decision == "reject":
           return {"data_gaps": [f"Skipped: {tool_name}"]}
   ```

4. **Map `slack_thread_ts` directly to `thread_id`** — this is the exact pattern LangGraph expects.

5. **Use `AsyncPostgresSaver` + `AsyncPostgresStore`** for production — handles concurrent Slack requests efficiently.

6. **Encrypt checkpoints** using `EncryptedSerializer` since the state will contain production metrics and error data from a regulated education platform.

7. **Structure the project** following LangGraph's recommended layout:
   ```
   gerbil_agent/
   ├── graphs/
   │   ├── intake.py           # Shared intake graph
   │   ├── release_report.py   # UC-2 graph
   │   ├── incident.py         # UC-1 graph
   │   ├── code_qa.py          # UC-3 graph
   │   └── docs_qa.py          # UC-4 graph
   ├── nodes/
   │   ├── approval.py         # Reusable approval gate
   │   ├── research.py         # Research phase nodes
   │   └── slack.py            # Slack interaction nodes
   ├── tools/
   │   ├── grafana.py          # Grafana MCP tools
   │   ├── bugsnag.py          # SmartBear MCP tools
   │   └── github.py           # GitHub MCP tools
   ├── state.py                # All TypedDict state schemas
   └── agent.py                # Graph composition & entry point
   ```

---

## Appendix: Key Packages

| Package | Purpose | Install |
|---|---|---|
| `langgraph` | Core framework | `pip install langgraph` |
| `langgraph-checkpoint-postgres` | PostgreSQL persistence | `pip install langgraph-checkpoint-postgres` |
| `langgraph-checkpoint-redis` | Redis persistence | `pip install langgraph-checkpoint-redis` |
| `langgraph-cli` | Dev server & CLI | `pip install "langgraph-cli[inmem]"` |
| `langgraph-sdk` | Remote client SDK | `pip install langgraph-sdk` |
| `langchain` | LLM abstractions, tools | `pip install langchain` |
| `langchain-anthropic` | Anthropic models | `pip install langchain-anthropic` |
| `langchain-openai` | OpenAI/Azure models | `pip install langchain-openai` |
| `psycopg[binary,pool]` | PostgreSQL driver | `pip install "psycopg[binary,pool]"` |
