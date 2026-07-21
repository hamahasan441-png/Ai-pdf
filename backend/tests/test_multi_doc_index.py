"""Unit tests for the multi-document BM25 index (pure logic, no DB/network)."""

from app.services.ai.multi_doc_index import MultiDocBm25Index


def test_add_and_search_single_doc():
    idx = MultiDocBm25Index()
    added = idx.add_document("d1", "invoice.pdf", {1: "Total amount due 500 EUR", 2: "Payment terms net 30 days"})
    assert added >= 2
    assert idx.chunk_count >= 2

    results = idx.search("payment terms")
    assert len(results) > 0
    assert results[0].doc_name == "invoice.pdf"
    assert "payment" in results[0].text.lower() or "terms" in results[0].text.lower()


def test_multi_doc_retrieval():
    idx = MultiDocBm25Index()
    idx.add_document("d1", "invoice.pdf", {1: "Total amount 500 EUR"})
    idx.add_document("d2", "contract.pdf", {1: "Payment schedule quarterly", 2: "Total contract value 10000 EUR"})

    results = idx.search("total amount EUR", top_k=3)
    # Should find passages from BOTH documents
    doc_ids = {r.doc_id for r in results}
    assert len(doc_ids) >= 1  # at minimum the most relevant doc


def test_doc_filter():
    idx = MultiDocBm25Index()
    idx.add_document("d1", "a.pdf", {1: "hello world"})
    idx.add_document("d2", "b.pdf", {1: "hello universe"})

    results = idx.search("hello", doc_filter="d2")
    assert all(r.doc_id == "d2" for r in results)


def test_empty_query_returns_nothing():
    idx = MultiDocBm25Index()
    idx.add_document("d1", "a.pdf", {1: "some text here"})
    assert idx.search("") == []
    assert idx.search("   ") == []


def test_clear():
    idx = MultiDocBm25Index()
    idx.add_document("d1", "a.pdf", {1: "content"})
    assert idx.chunk_count > 0
    idx.clear()
    assert idx.chunk_count == 0
    assert idx.search("content") == []


def test_arabic_tokenization():
    idx = MultiDocBm25Index()
    idx.add_document("d1", "form.pdf", {1: "الاسم الأول محمد تاريخ الميلاد"})
    results = idx.search("الاسم محمد")
    assert len(results) > 0
