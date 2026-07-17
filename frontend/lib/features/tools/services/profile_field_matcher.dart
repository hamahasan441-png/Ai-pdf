/// Offline, multilingual matcher that maps a detected form-field label to a
/// key in [UserProfileService.fields].
///
/// This is pure string matching — no network and no AI call — so the editor
/// can auto-fill known values instantly and privately (great for the free tier
/// and airplane-mode use). It is deliberately PRECISION-focused: a wrong
/// auto-fill is worse than a miss, so we avoid short ambiguous tokens (e.g.
/// bare "tel", "ort", "nation") that would match unrelated words.
///
/// Rules are checked in order; the first keyword found as a substring of the
/// (lower-cased) label wins. Order matters — e.g. "email" is checked before
/// "address" so an "Email address" label maps to email, not the street.
class ProfileFieldMatcher {
  ProfileFieldMatcher._();

  static const List<(List<String>, String)> _rules = [
    (
      ['first name', 'given name', 'forename', 'vorname', 'prénom', 'prenom',
        'nombre', 'الاسم الأول'],
      'first_name',
    ),
    (
      ['last name', 'surname', 'family name', 'nachname', 'familienname',
        'nom de famille', 'apellido', 'apellidos', 'اسم العائلة'],
      'last_name',
    ),
    (
      ['date of birth', 'birth date', 'birthday', 'dob', 'geburtsdatum',
        'geburtstag', 'date de naissance', 'fecha de nacimiento', 'تاريخ الميلاد'],
      'date_of_birth',
    ),
    (
      ['nationality', 'citizenship', 'staatsangehörigkeit', 'nationalité',
        'nacionalidad', 'الجنسية'],
      'nationality',
    ),
    (
      ['email', 'e-mail', 'correo', 'البريد'],
      'email',
    ),
    (
      ['phone', 'telephone', 'mobile', 'telefon', 'téléphone', 'telefono',
        'teléfono', 'الهاتف'],
      'phone_number',
    ),
    (
      ['postal code', 'post code', 'postcode', 'zip', 'plz', 'postleitzahl',
        'code postal', 'código postal', 'codigo postal', 'الرمز البريدي'],
      'postal_code',
    ),
    (
      ['address', 'street', 'anschrift', 'straße', 'strasse', 'adresse',
        'dirección', 'direccion', 'calle', 'العنوان'],
      'street_address',
    ),
    (
      ['city', 'town', 'stadt', 'ville', 'ciudad', 'المدينة'],
      'city',
    ),
    (
      ['country', 'pays', 'país', 'pais', 'الدولة'],
      'country',
    ),
    (
      ['passport', 'id number', 'identity', 'national id', 'reisepass',
        'ausweis', 'pasaporte', 'جواز'],
      'id_number',
    ),
    (
      ['employer', 'company', 'organization', 'organisation', 'arbeitgeber',
        'employeur', 'empresa', 'جهة العمل'],
      'employer_name',
    ),
    (
      ['job title', 'occupation', 'position', 'beruf', 'profession',
        'profesión', 'profesion', 'cargo', 'المهنة'],
      'job_title',
    ),
  ];

  /// Returns the matching [UserProfileService] key for [label], or null if
  /// nothing confidently matches.
  static String? match(String label) {
    final s = label.toLowerCase().replaceAll(':', ' ').trim();
    if (s.isEmpty) return null;
    for (final rule in _rules) {
      for (final kw in rule.$1) {
        if (s.contains(kw)) return rule.$2;
      }
    }
    return null;
  }
}
