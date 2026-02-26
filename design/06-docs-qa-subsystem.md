# Docs Q&A Subsystem Design

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## 1. Overview

The Docs Q&A subsystem answers natural-language questions about the Somtoday landscape, architecture, and operational documentation. It uses **Retrieval-Augmented Generation (RAG)**: a corpus of documents is indexed into a vector store; at query time, relevant chunks are retrieved and passed to the LLM alongside the question.

The subsystem is designed with a **generic adapter contract** so that additional sources (Confluence, docs websites, custom databases, additional Git repos) can be added without changing the graph or retrieval logic.

---

## 2. MVP Corpus

| Source | Type | MVP? | Future? |
|---|---|---|---|
| `topicusonderwijs/somtoday-docs` GitHub repo | Git repository | ✅ Yes | — |
| Confluence spaces | Wiki | — | ✅ Planned |
| docs.somtoday.nl or equivalent site | Website | — | ✅ Planned |
| Additional Git repositories | Git repository | — | ✅ Planned |
| Custom database / knowledge base | Database | — | ✅ Planned |
| This repo (`rapports/`, `template/`, `.github/`) | Git repository | — | ✅ Planned |

---

## 3. Generic Adapter Contract

All corpus sources implement the `CorpusAdapter` interface:

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass

@dataclass
class Document:
    id: str                   # unique: "source_type:path_or_url#section"
    content: str              # text content of the chunk
    metadata: dict            # source, title, url, last_modified, etc.

class CorpusAdapter(ABC):
    """Abstract base for all corpus sources."""

    @abstractmethod
    async def list_documents(self) -> list[Document]:
        """Return all documents (full text, before chunking)."""
        ...

    @abstractmethod
    async def get_document(self, doc_id: str) -> Document:
        """Fetch a single document by ID."""
        ...

    @property
    @abstractmethod
    def source_name(self) -> str:
        """Human-readable name, e.g. 'somtoday-docs Git repo'."""
        ...

    @property
    @abstractmethod
    def source_type(self) -> str:
        """Machine tag, e.g. 'github_repo', 'confluence', 'website'."""
        ...
```

The `IngestionPipeline` accepts any list of `CorpusAdapter` implementations:

```python
pipeline = IngestionPipeline(
    adapters=[GitRepoAdapter(repo="topicusonderwijs/somtoday-docs")],
    chunker=MarkdownChunker(chunk_size=500, overlap=50),
    embedder=OpenAIEmbedder(model="text-embedding-3-small"),
    vector_store=PgVectorStore(connection=POSTGRES_URL, table="docs_embeddings"),
)
```

Adding Confluence in the future:

```python
pipeline = IngestionPipeline(
    adapters=[
        GitRepoAdapter(repo="topicusonderwijs/somtoday-docs"),
        ConfluenceAdapter(space_key="SOM", base_url=CONFLUENCE_URL),  # new
    ],
    ...
)
```

---

## 4. MVP Adapter: `GitRepoAdapter`

### 4.1 Source

**Repository:** `topicusonderwijs/somtoday-docs`  
**Access:** GitHub PAT (same `github-mcp-secret` token with `contents:read` scope, or a separate read-only token)

### 4.2 Behaviour

1. List all Markdown (`.md`) and reStructuredText (`.rst`) files in the default branch.
2. Fetch file contents via the GitHub REST API (`GET /repos/{owner}/{repo}/git/trees/{sha}?recursive=1`).
3. Parse front-matter metadata (title, section, last_modified).
4. Pass documents to `MarkdownChunker`.

### 4.3 Change detection

On re-ingestion (scheduled nightly):
- Compare file SHAs in the tree against stored `last_indexed_sha` in the `corpus_metadata` table.
- Re-embed only changed or new files.
- Delete embeddings for deleted files.

---

## 5. Chunking Strategy

**Chunker:** `MarkdownChunker` — splits on headings (`##`, `###`) and then by character count.

| Parameter | Value |
|---|---|
| Max chunk size | 500 tokens |
| Overlap | 50 tokens |
| Split boundaries | Heading boundaries preferred; sentence boundaries as fallback |
| Metadata preserved | `source`, `repo`, `path`, `heading`, `url` (if available) |

Each chunk becomes one vector in the store. The `id` is `{repo}:{path}#{heading_slug}`.

---

## 6. Embedding and Vector Store

### 6.1 Embedding model

**MVP:** Provider-agnostic embedding (same abstraction as the LLM backend).  
Candidate: `text-embedding-3-small` (OpenAI) or `text-embedding-ada-002` (Azure OpenAI).  
Embedding dimension: 1536 (standard for both).

### 6.2 Vector store

**pgvector** extension on the same Postgres instance used for LangGraph checkpoints.

```sql
CREATE TABLE docs_embeddings (
    id          TEXT PRIMARY KEY,                -- chunk ID
    source      TEXT NOT NULL,                   -- source_name
    content     TEXT NOT NULL,                   -- chunk text
    metadata    JSONB,                           -- title, url, path, heading, ...
    embedding   VECTOR(1536) NOT NULL,
    indexed_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX ON docs_embeddings USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);
```

---

## 7. Retrieval at Query Time

```python
async def retrieve(question: str, k: int = 5) -> list[Document]:
    q_embedding = await embedder.embed(question)
    rows = await pg.fetch("""
        SELECT id, content, metadata,
               1 - (embedding <=> $1) AS score
        FROM docs_embeddings
        ORDER BY embedding <=> $1
        LIMIT $2
    """, q_embedding, k)
    return [Document(id=r["id"], content=r["content"], metadata=r["metadata"]) for r in rows]
```

Retrieved chunks are injected into the LLM prompt as:

```
## Relevant documentation

[Source: somtoday-docs / architectuur/authenticatie.md — §Authenticatie flow]
---
{chunk_content}
---
[Source: ...]
```

---

## 8. Ingestion Pipeline Lifecycle

### 8.1 Initial ingestion

Run as a Kubernetes **Job** at deployment time. Estimated duration: < 5 minutes for a typical docs repo.

### 8.2 Incremental updates

Kubernetes **CronJob** running nightly (e.g. 02:00 CET). Only changed files are re-processed.

### 8.3 Manual re-ingestion

`@gerbil reindex docs` command triggers an on-demand Job (operator approval required).

---

## 9. Source Citations

Every answer includes source citations linking back to the original document:

```
The authentication flow in Somtoday works as follows: [...]

Sources:
• somtoday-docs: architectuur/authenticatie.md §Authenticatie flow
  https://github.com/topicusonderwijs/somtoday-docs/blob/main/architectuur/authenticatie.md#authenticatie-flow
• somtoday-docs: api/oauth2.md §Token endpoints
  https://github.com/topicusonderwijs/somtoday-docs/blob/main/api/oauth2.md#token-endpoints
```

---

## 10. Future Adapters (Interface Only — Not MVP)

| Adapter | Key config |
|---|---|
| `ConfluenceAdapter` | `CONFLUENCE_URL`, `CONFLUENCE_TOKEN`, `space_key` |
| `WebsiteAdapter` | `start_url`, `allowed_domains`, crawl depth |
| `DatabaseAdapter` | `connection_string`, SQL query for document rows |
| `GitRepoAdapter` (additional repos) | Additional `repo` entries in adapter list |

Each adapter is a separate Python class implementing `CorpusAdapter`; registered in the `IngestionPipeline` config map.
