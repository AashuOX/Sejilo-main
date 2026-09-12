# Sejilo AI privacy architecture

The invariant is: messaging works without AI, and AI cannot weaken messaging.

AI is disabled by default and sits above decrypted local UI data. It is not a
transport, relay, key holder, authorization source, antivirus engine, or factual
network-state source. `AIProvider` separates local and future cloud providers.
Every request is bounded and contains an explicit selection; providers are not
given a global conversation/database handle.

The current build includes only a small deterministic `LocalAiProvider` for
draft rewriting, reply suggestions, short extractive summaries, draft-tone
cues, scam heuristics and sanitized diagnostic explanations. It is labeled
"On Device" and does not claim model-quality translation or understanding.
Translation, transcription, OCR, semantic search and model downloads remain
visibly unavailable until licensed, tested local providers exist.

Cloud AI is compile-time unavailable by default. A future cloud provider must:

1. require the master and Cloud AI toggles;
2. show the exact selected content, destination/provider, purpose and retention;
3. obtain fresh content-specific consent immediately before each operation;
4. send through an authenticated quota-limited server gateway with no provider
   API key in the client and no unrestricted tools/internal network access;
5. treat selected messages/files as prompt-injection input, not instructions;
6. exclude content from training and logging contractually and technically;
7. return labeled output that requires confirmation before any external action.

Derived local records have count/size quotas, use platform protected storage,
are removed with Clear AI Data, and expose a per-conversation deletion method.
Before semantic search or transcripts ship, conversation deletion must call
that method and tests must prove no orphaned derived records remain.
