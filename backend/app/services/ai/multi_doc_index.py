"""Multi-document BM25 index for cross-document reasoning.

Enables the /document-ai/chat endpoint to answer questions that span multiple
documents (e.g. "compare invoice totals" across 3 uploaded PDFs). The client
indexes documents locally via the on-device BM25 retriever; this server-side
implementation mirrors the same algorithm so managed-AI chat can also do
multi-doc retrieval without requiring the client to send all text upfront.

The index is per-session (in-memory) — it's created when documents are added
and discarded when the session ends. No document text is persisted server-side.
"""

import math
import re
from collections import Counter
from dataclasses import dataclass, field


@dataclass
class IndexedChunk:
    """A passage from a specific document + page."""
    doc_id: str
    doc_name: str
    page: int
    text: str
    tokens: list[str] = field(default_factory=list)


@dataclass
class RetrievedPassage:
    """A retrieved passage with its relevance score and source citation."""
    doc_id: str
    doc_name: str
    page: int
    text: str
    score: float


class MultiDocBm25Index:
    """BM25 (Okapi) index over multiple documents.

    Mirrors the on-device `bm25_retriever.dart` algorithm so scores are
    comparable. Parameters: k1=1.5, b=0.75 (standard).
    """

    def __init__(self, k1: float = 1.5, b: float = 0.75):
        self.k1 = k1
        self.b = b
        self._chunks: list[IndexedChunk] = []
        self._avg_dl: float = 0.0
        self._doc_freq: Counter[str] = Counter()
        self._n: int = 0

    @property
    def chunk_count(self) -> int:
        return self._n

    @property
    def doc_ids(self) -> set[str]:
        return {c.doc_id for c in self._chunks}

    def add_document(self, doc_id: str, doc_name: str, pages: dict[int, str],
                     chunk_size: int = 300) -> int:
        """Index a document's pages. Returns the number of chunks added."""
        added = 0
        for page_num, text in pages.items():
            for chunk_text in self._split_chunks(text, chunk_size):
                tokens = self._tokenize(chunk_text)
                if not tokens:
                    continue
                chunk = IndexedChunk(
                    doc_id=doc_id,
                    doc_name=doc_name,
                    page=page_num,
                    text=chunk_text,
                    tokens=tokens,
                )
                self._chunks.append(chunk)
                for t in set(tokens):
                    self._doc_freq[t] += 1
                added += 1
        self._n = len(self._chunks)
        self._avg_dl = (
            sum(len(c.tokens) for c in self._chunks) / self._n
            if self._n > 0
            else 0.0
        )
        return added

    def search(self, query: str, top_k: int = 5,
               doc_filter: str | None = None) -> list[RetrievedPassage]:
        """Retrieve the top-K most relevant passages across all indexed documents.

        Args:
            query: The user's question.
            top_k: Maximum passages to return.
            doc_filter: If set, only return passages from this doc_id.
        """
        query_tokens = self._tokenize(query)
        if not query_tokens or self._n == 0:
            return []

        scores: list[tuple[float, IndexedChunk]] = []
        for chunk in self._chunks:
            if doc_filter and chunk.doc_id != doc_filter:
                continue
            score = self._score(query_tokens, chunk)
            if score > 0:
                scores.append((score, chunk))

        scores.sort(key=lambda x: x[0], reverse=True)
        return [
            RetrievedPassage(
                doc_id=c.doc_id,
                doc_name=c.doc_name,
                page=c.page,
                text=c.text,
                score=s,
            )
            for s, c in scores[:top_k]
        ]

    def clear(self) -> None:
        """Drop all indexed data."""
        self._chunks.clear()
        self._doc_freq.clear()
        self._n = 0
        self._avg_dl = 0.0

    # ── Internal ──────────────────────────────────────────────────────────

    def _score(self, query_tokens: list[str], chunk: IndexedChunk) -> float:
        """BM25 score for a single chunk against the query."""
        dl = len(chunk.tokens)
        score = 0.0
        tf_map = Counter(chunk.tokens)
        for qt in query_tokens:
            if qt not in tf_map:
                continue
            tf = tf_map[qt]
            df = self._doc_freq.get(qt, 0)
            idf = math.log((self._n - df + 0.5) / (df + 0.5) + 1.0)
            numerator = tf * (self.k1 + 1)
            denominator = tf + self.k1 * (1 - self.b + self.b * dl / self._avg_dl)
            score += idf * numerator / denominator
        return score

    @staticmethod
    def _tokenize(text: str) -> list[str]:
        """Lowercase + split on non-alphanumeric (matches the Dart BM25)."""
        return [t for t in re.split(r'[^a-zA-Z0-9\u0600-\u06FF]+', text.lower()) if len(t) > 1]

    @staticmethod
    def _split_chunks(text: str, size: int) -> list[str]:
        """Split text into overlapping chunks of ~size words."""
        words = text.split()
        if len(words) <= size:
            return [text] if words else []
        chunks = []
        step = max(1, size // 2)  # 50% overlap
        for i in range(0, len(words), step):
            chunk = ' '.join(words[i:i + size])
            if chunk.strip():
                chunks.append(chunk)
        return chunks
