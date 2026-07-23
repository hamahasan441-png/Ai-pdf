import 'package:flutter/material.dart';

/// Form Template Gallery — pre-made fillable form templates users can instantly
/// open and fill with their profile data (zero manual setup).
///
/// Categories: Government, Medical, Legal, Education, Business, Personal.
/// Each template has metadata: name, category, language, fields list.
/// Tapping a template opens it in the editor with Smart Fill pre-applied.
class TemplateGalleryScreen extends StatefulWidget {
  const TemplateGalleryScreen({super.key});

  @override
  State<TemplateGalleryScreen> createState() => _TemplateGalleryScreenState();
}

class _TemplateGalleryScreenState extends State<TemplateGalleryScreen> {
  _Category _selectedCategory = _Category.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _selectedCategory == _Category.all
        ? _templates
        : _templates.where((t) => t.category == _selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Form Templates')),
      body: Column(
        children: [
          // Category chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _Category.values.map((cat) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    selected: _selectedCategory == cat,
                    label: Text(cat.label),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Template grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final t = filtered[i];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openTemplate(t),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            color: t.category.color.withOpacity(0.1),
                            child: Icon(t.category.icon, size: 48, color: t.category.color),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text('${t.fieldCount} fields • ${t.language}', style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openTemplate(_Template t) {
    // In production: load the template PDF, open in editor with Smart Fill.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening "${t.name}"…')),
    );
  }
}

enum _Category {
  all('All', Icons.apps, Colors.grey),
  government('Government', Icons.account_balance, Colors.blue),
  medical('Medical', Icons.local_hospital, Colors.red),
  legal('Legal', Icons.gavel, Colors.brown),
  education('Education', Icons.school, Colors.green),
  business('Business', Icons.business, Colors.orange),
  personal('Personal', Icons.person, Colors.purple);

  final String label;
  final IconData icon;
  final Color color;
  const _Category(this.label, this.icon, this.color);
}

class _Template {
  final String name;
  final _Category category;
  final String language;
  final int fieldCount;
  const _Template(this.name, this.category, this.language, this.fieldCount);
}

const _templates = [
  _Template('Iraqi ID Application', _Category.government, 'Kurdish/Arabic', 24),
  _Template('Passport Renewal', _Category.government, 'Arabic/English', 18),
  _Template('Driver License Form', _Category.government, 'Kurdish', 15),
  _Template('Medical Record', _Category.medical, 'Arabic/English', 32),
  _Template('Patient Intake Form', _Category.medical, 'Kurdish', 20),
  _Template('Prescription Form', _Category.medical, 'Arabic', 12),
  _Template('Rental Agreement', _Category.legal, 'Kurdish/Arabic', 28),
  _Template('Employment Contract', _Category.legal, 'Arabic/English', 35),
  _Template('Power of Attorney', _Category.legal, 'Arabic', 16),
  _Template('University Enrollment', _Category.education, 'Kurdish', 22),
  _Template('Grade Transcript Request', _Category.education, 'Arabic', 10),
  _Template('Invoice Template', _Category.business, 'English', 14),
  _Template('Expense Report', _Category.business, 'English', 18),
  _Template('Personal Budget', _Category.personal, 'English', 8),
  _Template('Travel Visa Application', _Category.government, 'English/Arabic', 30),
];
