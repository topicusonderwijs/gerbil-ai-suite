# ADR-004: LLM Provider Abstraction

**Date:** 2026-02-26  
**Status:** Accepted  
**Deciders:** Gerbil AI Suite team

---

## Context

The agent requires a capable LLM for intent classification, research synthesis, and answer generation. The existing VS Code suite runs on GitHub Copilot (which transparently uses GPT-4o or Claude models). For an autonomous Kubernetes service, an explicit provider choice is required — and that choice has cost, data-residency, and dependency implications for a school administration platform.

Options considered:

| Option | Description | Pros | Cons |
|---|---|---|---|
| A: Azure OpenAI only | Hard-code Azure OpenAI calls | EU data residency; enterprise support | Lock-in; single point of failure |
| B: OpenAI API only | Hard-code OpenAI API calls | Simpler config | Data residency concerns for NL school data |
| C: Anthropic API only | Hard-code Anthropic Claude | Strong reasoning; large context | Newer provider; EU residency less established |
| D: Provider-agnostic (LangChain `BaseChatModel`) | Abstract behind LangChain's model interface; configure provider via env var | No lock-in; swap without code changes; test with cheaper models | Slightly more initial setup |

---

## Decision

**Option D: Provider-agnostic via LangChain `BaseChatModel`**.

```python
from langchain_core.language_models import BaseChatModel

def create_llm() -> BaseChatModel:
    provider = os.environ["LLM_PROVIDER"]
    if provider == "azure_openai":
        from langchain_openai import AzureChatOpenAI
        return AzureChatOpenAI(
            azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
            api_key=os.environ["AZURE_OPENAI_API_KEY"],
            deployment_name=os.environ["AZURE_OPENAI_DEPLOYMENT"],
        )
    elif provider == "openai":
        from langchain_openai import ChatOpenAI
        return ChatOpenAI(api_key=os.environ["OPENAI_API_KEY"], model="gpt-4o")
    elif provider == "anthropic":
        from langchain_anthropic import ChatAnthropic
        return ChatAnthropic(api_key=os.environ["ANTHROPIC_API_KEY"], model="claude-opus-4-5")
    else:
        raise ValueError(f"Unknown LLM_PROVIDER: {provider}")
```

The `LLM_PROVIDER` environment variable is set at the cluster level via the `llm-secret` Kubernetes Secret.

**Recommended first provider:** Azure OpenAI (EU region), chosen when the implementation sprint begins and the team confirms data processing agreements.

---

## Consequences

- All LangGraph nodes receive the `BaseChatModel` instance via dependency injection; no provider-specific code in graph nodes.
- The embedding model (for docs Q&A) follows the same abstraction via `langchain_core.embeddings.Embeddings`.
- Provider can be changed by updating the `llm-secret` and restarting the pod; no code change required.
- New providers (e.g., Google Vertex, local Ollama) can be added to `create_llm()` without affecting the rest of the codebase.
- Model capability requirements (large context window ≥ 32k tokens for synthesis phase) must be validated per provider before selecting a deployment name.

---

## Review trigger

Re-evaluate if a provider introduces breaking API changes, if data residency requirements change, or if a new model demonstrates significantly better performance on the synthesis task.
