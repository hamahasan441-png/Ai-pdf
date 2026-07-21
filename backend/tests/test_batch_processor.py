"""Tests for the batch form processor."""

from app.services.ai.batch_processor import batch_processor


def test_batch_single_form():
    docs = [{
        "name": "form1.pdf",
        "fields": [
            {"label": "Vorname", "type": "name"},
            {"label": "Email", "type": "email"},
        ],
    }]
    profile = {"first_name": "Ahmad", "email": "ahmad@example.com"}
    results = batch_processor.process_batch(docs, profile)
    assert len(results) == 1
    assert results[0].fields_detected == 2
    assert results[0].fields_filled >= 1


def test_batch_multiple_forms():
    docs = [
        {"name": "form1.pdf", "fields": [{"label": "Name", "type": "name"}]},
        {"name": "form2.pdf", "fields": [{"label": "Email", "type": "email"}]},
    ]
    profile = {"full_name": "Ahmad Ali", "email": "a@b.com"}
    results = batch_processor.process_batch(docs, profile)
    assert len(results) == 2
    assert results[0].doc_name == "form1.pdf"
    assert results[1].doc_name == "form2.pdf"


def test_batch_validation_error():
    docs = [{"name": "form.pdf", "fields": [{"label": "email", "type": "email"}]}]
    profile = {"email": "not-valid"}
    results = batch_processor.process_batch(docs, profile)
    assert results[0].validation_errors != []


def test_batch_empty():
    results = batch_processor.process_batch([], {})
    assert results == []


def test_batch_custom_mapping():
    docs = [{"name": "f.pdf", "fields": [{"label": "Kontakt-E-Mail", "type": "email"}]}]
    profile = {"email": "test@test.com"}
    results = batch_processor.process_batch(
        docs, profile, field_mappings={"Kontakt-E-Mail": "email"}
    )
    assert results[0].filled_values.get("Kontakt-E-Mail") == "test@test.com"
