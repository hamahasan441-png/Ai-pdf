"""Map-reduce summarization for large documents.

When a document exceeds the context window (e.g. 50+ pages), naive summarization
loses information from the middle. This service:
1. MAP: summarizes each chunk independently (parallel-friendly)
2. REDUCE: combines the chunk summaries into one coherent final summary

This matches the approach used by LangChain/LlamaIndex and ensures no part of a
long document is lost in the summary.
"""

from app.services.ai.provider import ai_provider


async def map_reduce_summarize(
    text: str,
    chunk_size: int = 3000,
    style: str = "structured",
    language: str = "auto",
) -> str:
    """Summarize a long document using map-reduce.

    Args:
        text: The full document text (can be very long).
        chunk_size: Characters per chunk for the map step.
        style: structured | brief | bullet
        language: Target language for the summary (auto = same as source).

    Returns:
        A coherent summary covering the entire document.
    """
    chunks = _split_text(text, chunk_size)

    if len(chunks) <= 1:
        # Short document — direct summarization (no map-reduce needed).
        return await _summarize_single(text, style, language)

    # MAP: summarize each chunk
    chunk_summaries = []
    for i, chunk in enumerate(chunks):
        summary = await _summarize_chunk(chunk, i + 1, len(chunks), language)
        chunk_summaries.append(summary)

    # REDUCE: combine chunk summaries into a final summary
    combined = "\n\n".join(
        f"[Section {i+1}/{len(chunk_summaries)}]\n{s}"
        for i, s in enumerate(chunk_summaries)
    )
    return await _reduce_summaries(combined, style, language)


async def _summarize_chunk(chunk: str, part: int, total: int, language: str) -> str:
    """MAP step: summarize one chunk."""
    lang_hint = f" Respond in {language}." if language != "auto" else ""
    messages = [
        {
            "role": "system",
            "content": (
                f"Summarize this section (part {part}/{total}) of a longer document. "
                "Capture ALL key facts, names, dates, amounts, and decisions. "
                f"Be thorough — nothing should be lost.{lang_hint}"
            ),
        },
        {"role": "user", "content": chunk},
    ]
    return await ai_provider.chat_completion(
        messages=messages, temperature=0.1, max_tokens=1024
    )


async def _reduce_summaries(combined: str, style: str, language: str) -> str:
    """REDUCE step: combine chunk summaries into one coherent final summary."""
    lang_hint = f" Respond in {language}." if language != "auto" else ""
    style_instruction = {
        "structured": "1) Document type, 2) Key points (bullets), 3) Important entities, 4) Action items.",
        "brief": "A concise 3-5 sentence summary.",
        "bullet": "A bullet-point summary with one key fact per bullet.",
    }.get(style, "A clear, comprehensive summary.")

    messages = [
        {
            "role": "system",
            "content": (
                "You are combining section summaries of a long document into ONE "
                f"coherent final summary. Format: {style_instruction}{lang_hint} "
                "Do not mention that these are section summaries — write as if "
                "summarizing the original document directly."
            ),
        },
        {"role": "user", "content": combined},
    ]
    return await ai_provider.chat_completion(
        messages=messages, temperature=0.2, max_tokens=2048
    )


async def _summarize_single(text: str, style: str, language: str) -> str:
    """Direct summarization for short documents (no map-reduce needed)."""
    lang_hint = f" Respond in {language}." if language != "auto" else ""
    style_instruction = {
        "structured": "1) Document type, 2) Key points (bullets), 3) Important entities, 4) Action items.",
        "brief": "A concise 2-3 sentence summary.",
        "bullet": "A bullet-point summary with one key fact per bullet.",
    }.get(style, "Summarize clearly.")

    messages = [
        {"role": "system", "content": f"You are an expert summarizer.{lang_hint}"},
        {"role": "user", "content": f"{style_instruction}\n\nDocument:\n{text[:12000]}"},
    ]
    return await ai_provider.chat_completion(
        messages=messages, temperature=0.2, max_tokens=2048
    )


async def stream_map_reduce_summarize(
    text: str,
    chunk_size: int = 3000,
    style: str = "structured",
    language: str = "auto",
):
    """Generator that yields SSE events for streaming map-reduce summarization.

    Yields dicts: {"type": "chunk", "index": int, "total": int, "summary": str}
    and finally {"type": "final", "summary": str, "chunks": int}

    This implements E2.2 streaming (see ENHANCEMENT_BASED_MASTERPLAN.md).
    """
    chunks = _split_text(text, chunk_size)

    if len(chunks) <= 1:
        final = await _summarize_single(text, style, language)
        yield {"type": "final", "summary": final, "chunks": 1, "cited": []}
        return

    chunk_summaries = []
    for i, chunk in enumerate(chunks):
        summary = await _summarize_chunk(chunk, i + 1, len(chunks), language)
        chunk_summaries.append(summary)
        # Yield each chunk summary as soon as it's ready (first chunk <10s)
        yield {
            "type": "chunk",
            "index": i + 1,
            "total": len(chunks),
            "summary": summary,
            "page_citation": {"chunk": i + 1, "chars": f"{i*chunk_size}-{(i+1)*chunk_size}"},
        }

    combined = "\n\n".join(
        f"[Section {i+1}/{len(chunk_summaries)}]\n{s}" for i, s in enumerate(chunk_summaries)
    )
    final = await _reduce_summaries(combined, style, language)
    yield {"type": "final", "summary": final, "chunks": len(chunks), "cited": list(range(1, len(chunks) + 1))}


def _split_text(text: str, chunk_size: int) -> list[str]:
    """Split text into chunks, preferring sentence boundaries."""
    if len(text) <= chunk_size:
        return [text]
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + chunk_size, len(text))
        # Try to break at a sentence boundary
        if end < len(text):
            for sep in ['. ', '.\n', '\n\n', '\n', ' ']:
                boundary = text.rfind(sep, start + chunk_size // 2, end)
                if boundary > start:
                    end = boundary + len(sep)
                    break
        chunks.append(text[start:end])
        start = end
    return chunks
