/// AI Document Classifier — categorizes documents by type using on-device
/// heuristics (keyword matching + structure analysis).
///
/// Categories: Invoice, Contract, ID/Passport, Medical, Legal, Academic,
/// Letter, Form, Receipt, Report, Certificate, Other.
///
/// Used for:
/// - Auto-organizing the library
/// - Suggesting the right form template
/// - Applying category-specific AI prompts
/// - Smart folder assignment
class DocumentClassifierService {
  const DocumentClassifierService();

  /// Classify a document from its OCR text.
  DocumentCategory classify(String text) {
    if (text.trim().isEmpty) return DocumentCategory.other;

    final lower = text.toLowerCase();
    final scores = <DocumentCategory, int>{};

    for (final category in DocumentCategory.values) {
      if (category == DocumentCategory.other) continue;
      int score = 0;
      for (final keyword in category.keywords) {
        score += RegExp(keyword, caseSensitive: false).allMatches(lower).length;
      }
      if (score > 0) scores[category] = score;
    }

    if (scores.isEmpty) return DocumentCategory.other;

    // Return the highest-scoring category.
    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  /// Classify and return confidence (0.0 to 1.0).
  ClassificationResult classifyWithConfidence(String text) {
    if (text.trim().isEmpty) {
      return const ClassificationResult(DocumentCategory.other, 0.0);
    }

    final lower = text.toLowerCase();
    final scores = <DocumentCategory, int>{};
    int totalMatches = 0;

    for (final category in DocumentCategory.values) {
      if (category == DocumentCategory.other) continue;
      int score = 0;
      for (final keyword in category.keywords) {
        score += RegExp(keyword, caseSensitive: false).allMatches(lower).length;
      }
      scores[category] = score;
      totalMatches += score;
    }

    if (totalMatches == 0) {
      return const ClassificationResult(DocumentCategory.other, 0.0);
    }

    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final best = sorted.first;
    final confidence = (best.value / totalMatches).clamp(0.0, 1.0);
    return ClassificationResult(best.key, confidence);
  }
}

/// Document category with associated detection keywords.
enum DocumentCategory {
  invoice(['invoice', 'bill', 'total', 'amount due', 'payment', 'فاتورە', 'فاتورة']),
  contract(['agreement', 'contract', 'party', 'whereas', 'witness', 'گرێبەست', 'عقد']),
  idPassport(['passport', 'national id', 'identity', 'nationality', 'ناسنامە', 'جواز']),
  medical(['patient', 'diagnosis', 'prescription', 'doctor', 'hospital', 'نەخۆش', 'طبيب']),
  legal(['court', 'plaintiff', 'defendant', 'judgment', 'law', 'دادگا', 'محكمة']),
  academic(['university', 'student', 'grade', 'semester', 'thesis', 'زانکۆ', 'جامعة']),
  letter(['dear', 'sincerely', 'regards', 'subject:', 'بەڕێز', 'عزيزي']),
  form(['fill', 'checkbox', 'signature', 'date:', 'name:', 'ناو:', 'الاسم']),
  receipt(['receipt', 'paid', 'change', 'cash', 'وەصڵ', 'إيصال']),
  report(['report', 'summary', 'findings', 'conclusion', 'ڕاپۆرت', 'تقرير']),
  certificate(['certificate', 'certify', 'awarded', 'بڕوانامە', 'شهادة']),
  other([]);

  final List<String> keywords;
  const DocumentCategory(this.keywords);
}

class ClassificationResult {
  final DocumentCategory category;
  final double confidence;
  const ClassificationResult(this.category, this.confidence);
}
