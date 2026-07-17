/// The kind of value a field expects. Drives on-device validation (e.g. an
/// email field must contain '@') and lets the matcher pull typed loose values
/// (emails, dates, IBANs…) out of the info document even when they have no
/// explicit label.
enum ValueKind {
  name,
  date,
  email,
  phone,
  number,
  postalCode,
  iban,
  idNumber,
  city,
  country,
  place,
  street,
  gender,
  text,
  signature,
}

class _Entry {
  final List<String> kw;
  final String key;
  final ValueKind kind;
  const _Entry(this.kw, this.key, this.kind);
}

/// A compact, fully offline ontology mapping form-field LABELS (German +
/// English, with common diacritic-free spellings) to a canonical field key and
/// its [ValueKind].
///
/// Entries are ordered most-specific first, so "first name / Vorname" wins over
/// the generic "name", and "date of birth / Geburtsdatum" wins over "date /
/// Datum". Matching is pure substring containment on a normalized label — no
/// network, no model — so it is instant and private, and easy to extend.
class FormOntology {
  FormOntology._();

  static const List<_Entry> _entries = [
    // --- dates / birth (specific before generic "date") ---
    _Entry(['date of birth', 'geburtsdatum', 'geburtstag', 'geboren am',
        'birth date', 'birthday', 'fecha de nacimiento', 'dob'],
        'date_of_birth', ValueKind.date),
    _Entry(['place of birth', 'geburtsort', 'birthplace', 'geburtsland'],
        'place_of_birth', ValueKind.place),

    // --- names (first/last before the bare "name" -> full name) ---
    _Entry(['first name', 'given name', 'forename', 'vorname', 'prenom',
        'prénom', 'nombre'], 'first_name', ValueKind.name),
    _Entry(['last name', 'surname', 'family name', 'nachname', 'familienname',
        'nom de famille', 'apellidos', 'apellido'], 'last_name', ValueKind.name),
    _Entry(['geburtsname', 'birth name', 'maiden name', 'mädchenname',
        'madchenname'], 'birth_name', ValueKind.name),
    _Entry(['name des ehegatten', 'ehegatte', 'ehepartner', 'ehefrau',
        'ehemann', 'spouse'], 'spouse_name', ValueKind.name),
    _Entry(['full name', 'vollständiger name', 'vollstandiger name',
        'vor- und nachname', 'name and surname', 'name'], 'full_name',
        ValueKind.name),

    // --- personal ---
    _Entry(['nationality', 'citizenship', 'staatsangehörigkeit',
        'staatsangehorigkeit', 'nationalität', 'nationalitat', 'nacionalidad'],
        'nationality', ValueKind.text),
    _Entry(['gender', 'sex', 'geschlecht'], 'gender', ValueKind.gender),
    _Entry(['marital status', 'familienstand', 'civil status', 'estado civil'],
        'marital_status', ValueKind.text),

    // --- contact ---
    _Entry(['e-mail', 'email', 'e mail', 'correo'], 'email', ValueKind.email),
    _Entry(['telephone', 'phone', 'telefon', 'téléphone', 'telefono',
        'teléfono', 'mobile', 'mobil', 'handy'], 'phone_number',
        ValueKind.phone),
    _Entry(['telefax', 'faxnummer', 'fax'], 'fax', ValueKind.phone),

    // --- address ---
    _Entry(['postal code', 'post code', 'postcode', 'postleitzahl', 'plz',
        'zip', 'código postal', 'codigo postal'], 'postal_code',
        ValueKind.postalCode),
    _Entry(['hausnummer', 'house number', 'haus-nr', 'hausnr', 'house no'],
        'house_number', ValueKind.number),
    _Entry(['street address', 'street', 'straße', 'strasse', 'anschrift',
        'adresse', 'address', 'dirección', 'direccion'], 'street_address',
        ValueKind.street),
    _Entry(['city', 'town', 'wohnort', 'ort', 'stadt', 'ciudad'], 'city',
        ValueKind.city),
    _Entry(['country', 'staat', 'land', 'pays', 'país', 'pais'], 'country',
        ValueKind.country),

    // --- ids / tax / banking ---
    _Entry(['steueridentifikationsnummer', 'steuer-id', 'steuer id', 'steuerid',
        'tax identification', 'tax id', 'steuernummer', 'tax number'], 'tax_id',
        ValueKind.number),
    _Entry(['sozialversicherungsnummer', 'social security', 'sv-nummer',
        'versicherungsnummer', 'insurance number'], 'social_security',
        ValueKind.number),
    _Entry(['passport', 'reisepass', 'passnummer'], 'passport_number',
        ValueKind.idNumber),
    _Entry(['id number', 'identity card', 'personalausweis', 'ausweisnummer',
        'ausweis', 'identity', 'id no'], 'id_number', ValueKind.idNumber),
    _Entry(['iban'], 'iban', ValueKind.iban),
    _Entry(['kontonummer', 'konto-nr', 'kontonr', 'account number'],
        'bank_account', ValueKind.number),
    _Entry(['bic', 'swift'], 'bic', ValueKind.text),
    _Entry(['krankenkasse', 'krankenversicherung', 'health insurance',
        'gesundheitskasse'], 'health_insurance', ValueKind.text),
    _Entry(['bank', 'kreditinstitut'], 'bank_name', ValueKind.text),

    // --- work ---
    _Entry(['employer', 'arbeitgeber', 'company', 'firma', 'unternehmen',
        'empresa'], 'employer_name', ValueKind.text),
    _Entry(['job title', 'occupation', 'beruf', 'position', 'tätigkeit',
        'tatigkeit', 'profession', 'profesión', 'profesion'], 'job_title',
        ValueKind.text),

    // --- signature / generic date (most generic, checked last) ---
    _Entry(['signature', 'unterschrift', 'sign here', 'signed'], 'signature',
        ValueKind.signature),
    _Entry(['date', 'datum', 'fecha'], 'date_today', ValueKind.date),
  ];

  static final Map<String, ValueKind> _kindByKey = {
    for (final e in _entries) e.key: e.kind,
  };

  /// Normalize a label for matching: lower-case, turn separators into spaces,
  /// collapse whitespace. Diacritics are preserved (keyword lists include both
  /// accented and ASCII spellings).
  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[:._,/]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Canonical field key for [label], or null if nothing matches.
  static String? match(String label) {
    final s = _norm(label);
    if (s.isEmpty) return null;
    for (final e in _entries) {
      for (final k in e.kw) {
        if (s.contains(k)) return e.key;
      }
    }
    return null;
  }

  /// The [ValueKind] expected by a canonical [key].
  static ValueKind kindOf(String key) => _kindByKey[key] ?? ValueKind.text;
}
