"""Semantic Field Mapper - Maps form fields to profile data in ANY language.

Understands that all these mean "Last Name":
- English: Last Name, Surname, Family Name
- German: Nachname, Familienname
- French: Nom de famille, Nom
- Spanish: Apellido, Apellidos
- Arabic: اسم العائلة, الاسم الأخير
- Chinese: 姓, 姓氏
- Turkish: Soyad, Soyadı
- Japanese: 姓, 名字
- Portuguese: Sobrenome, Apelido
- Italian: Cognome
- Dutch: Achternaam
- Russian: Фамилия

100+ field types supported with intelligent matching.
"""

import logging
from typing import Any, Optional

from app.services.ai.provider import ai_provider

logger = logging.getLogger(__name__)

# Comprehensive multi-language field mapping prompt
FIELD_MAPPING_PROMPT = """You are a multilingual form field mapping expert. You understand form fields in ALL languages and can map them to standardized profile data fields.

AVAILABLE PROFILE FIELDS:
- first_name: First/given name
- last_name: Last/family name  
- full_name: Full name combined
- middle_name: Middle name
- date_of_birth: Date of birth
- gender: Gender/sex
- nationality: Nationality/citizenship
- marital_status: Marital status
- phone: Phone number (primary)
- secondary_phone: Secondary phone
- email: Email address
- address: Street address (line 1)
- address_line_2: Address line 2 (apt, suite)
- city: City/town
- state: State/province/region
- zip_code: ZIP/postal code
- country: Country
- passport_number: Passport number
- passport_expiry: Passport expiry date
- passport_country: Passport issuing country
- national_id: National ID number
- drivers_license: Driver's license number
- ssn: Social security number / Tax ID
- employer_name: Employer/company name
- job_title: Job title/position
- employer_address: Employer address
- employment_start: Employment start date
- annual_salary: Annual salary/income
- bank_name: Bank name
- account_number: Bank account number
- routing_number: Bank routing number
- iban: IBAN
- insurance_provider: Insurance company
- insurance_number: Insurance policy number
- emergency_contact_name: Emergency contact name
- emergency_contact_phone: Emergency contact phone
- education_level: Highest education level
- university: University/school name
- degree: Degree title
- graduation_year: Graduation year

MULTILINGUAL UNDERSTANDING RULES:
- "Vorname" (DE) = "Prénom" (FR) = "Nombre" (ES) = "الاسم الأول" (AR) = first_name
- "Nachname" (DE) = "Nom" (FR) = "Apellido" (ES) = "اسم العائلة" (AR) = last_name
- "Geburtsdatum" (DE) = "Date de naissance" (FR) = "Fecha de nacimiento" (ES) = date_of_birth
- "Anschrift"/"Straße" (DE) = "Adresse" (FR) = "Dirección" (ES) = address
- "Telefon" (DE) = "Téléphone" (FR) = "Teléfono" (ES) = phone
- "Beruf" (DE) = "Profession" (FR) = "Profesión" (ES) = job_title
- "Arbeitgeber" (DE) = "Employeur" (FR) = "Empleador" (ES) = employer_name

Return JSON with mappings. Be generous with matching - if there's a reasonable connection, map it.

{
  "mappings": [
    {
      "field_name": "original field name",
      "profile_field": "matched profile field or null",
      "confidence": 0.0-1.0,
      "language_detected": "field language",
      "semantic_meaning": "what the field is asking for in English"
    }
  ]
}"""


# Direct mapping table for instant matching (no AI call needed)
INSTANT_MAPPINGS = {
    # English
    "first name": "first_name", "given name": "first_name", "forename": "first_name",
    "last name": "last_name", "surname": "last_name", "family name": "last_name",
    "full name": "full_name", "name": "full_name",
    "middle name": "middle_name", "middle initial": "middle_name",
    "date of birth": "date_of_birth", "dob": "date_of_birth", "birth date": "date_of_birth", "birthday": "date_of_birth",
    "gender": "gender", "sex": "gender",
    "nationality": "nationality", "citizenship": "nationality",
    "marital status": "marital_status",
    "phone": "phone", "phone number": "phone", "telephone": "phone", "mobile": "phone", "cell": "phone", "mobile phone": "phone",
    "email": "email", "email address": "email", "e-mail": "email",
    "address": "address", "street": "address", "street address": "address", "address line 1": "address",
    "apartment": "address_line_2", "apt": "address_line_2", "suite": "address_line_2", "unit": "address_line_2",
    "city": "city", "town": "city",
    "state": "state", "province": "state", "region": "state",
    "zip": "zip_code", "zip code": "zip_code", "postal code": "zip_code", "postcode": "zip_code",
    "country": "country", "nation": "country",
    "passport number": "passport_number", "passport no": "passport_number", "passport #": "passport_number",
    "passport expiry": "passport_expiry", "passport expiration": "passport_expiry",
    "national id": "national_id", "id number": "national_id", "identity number": "national_id",
    "driver license": "drivers_license", "drivers license": "drivers_license", "driving license": "drivers_license",
    "ssn": "ssn", "social security": "ssn", "social security number": "ssn", "tax id": "ssn", "tin": "ssn",
    "employer": "employer_name", "company": "employer_name", "company name": "employer_name", "organization": "employer_name",
    "job title": "job_title", "position": "job_title", "occupation": "job_title", "title": "job_title", "role": "job_title",
    "salary": "annual_salary", "income": "annual_salary", "annual income": "annual_salary", "annual salary": "annual_salary",
    "bank": "bank_name", "bank name": "bank_name",
    "account number": "account_number", "account no": "account_number",
    "iban": "iban", "routing number": "routing_number",
    "insurance": "insurance_provider", "insurer": "insurance_provider",
    "policy number": "insurance_number",
    "emergency contact": "emergency_contact_name",
    "education": "education_level", "highest education": "education_level",
    "university": "university", "school": "university", "college": "university",
    "degree": "degree",
    "graduation year": "graduation_year", "year of graduation": "graduation_year",
    # German
    "vorname": "first_name", "nachname": "last_name", "familienname": "last_name",
    "geburtsdatum": "date_of_birth", "geburtstag": "date_of_birth",
    "geschlecht": "gender", "staatsangehörigkeit": "nationality",
    "familienstand": "marital_status", "telefon": "phone", "telefonnummer": "phone",
    "straße": "address", "anschrift": "address", "adresse": "address",
    "stadt": "city", "ort": "city", "plz": "zip_code", "postleitzahl": "zip_code",
    "land": "country", "beruf": "job_title", "arbeitgeber": "employer_name",
    "reisepassnummer": "passport_number", "personalausweis": "national_id",
    # French
    "prénom": "first_name", "nom": "last_name", "nom de famille": "last_name",
    "date de naissance": "date_of_birth", "sexe": "gender",
    "nationalité": "nationality", "état civil": "marital_status",
    # "adresse" is already mapped in the German block above (same value);
    # French keeps "rue" -> address to avoid a duplicate dict key.
    "téléphone": "phone", "rue": "address",
    "ville": "city", "code postal": "zip_code", "pays": "country",
    "profession": "job_title", "employeur": "employer_name",
    "numéro de passeport": "passport_number",
    # Spanish
    "nombre": "first_name", "apellido": "last_name", "apellidos": "last_name",
    "fecha de nacimiento": "date_of_birth", "sexo": "gender",
    "nacionalidad": "nationality", "estado civil": "marital_status",
    "teléfono": "phone", "dirección": "address", "calle": "address",
    "ciudad": "city", "código postal": "zip_code", "país": "country",
    "profesión": "job_title", "empresa": "employer_name",
    "número de pasaporte": "passport_number",
    # Arabic
    "الاسم الأول": "first_name", "اسم العائلة": "last_name", "الاسم الكامل": "full_name",
    "تاريخ الميلاد": "date_of_birth", "الجنس": "gender",
    "الجنسية": "nationality", "الحالة الاجتماعية": "marital_status",
    "رقم الهاتف": "phone", "العنوان": "address",
    "المدينة": "city", "الرمز البريدي": "zip_code", "الدولة": "country",
    "المهنة": "job_title", "جهة العمل": "employer_name",
    "رقم جواز السفر": "passport_number",
}


class FieldMapper:
    """Maps document form fields to user profile fields using AI + direct mapping.

    Two-phase approach:
    1. Instant mapping: Direct keyword match (fast, no AI call)
    2. AI mapping: For complex/ambiguous fields (semantic understanding)
    """

    async def map_fields(
        self, form_fields: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        """Map form fields to profile fields.

        First tries instant mapping, then uses AI for unmapped fields.
        """
        if not form_fields:
            return []

        results = []
        unmapped_fields = []

        # Phase 1: Instant mapping
        for f in form_fields:
            name = (f.get("field_name") or f.get("field_label") or f.get("label") or "").strip()
            normalized = name.lower().strip()

            # Try direct match
            profile_field = INSTANT_MAPPINGS.get(normalized)

            if profile_field:
                results.append({
                    "field_name": name,
                    "profile_field": profile_field,
                    "confidence": 0.95,
                    "language_detected": "auto",
                    "semantic_meaning": profile_field.replace("_", " "),
                })
            else:
                # Try partial match
                matched = self._try_partial_match(normalized)
                if matched:
                    results.append({
                        "field_name": name,
                        "profile_field": matched,
                        "confidence": 0.8,
                        "language_detected": "auto",
                        "semantic_meaning": matched.replace("_", " "),
                    })
                else:
                    unmapped_fields.append(f)
                    results.append({"field_name": name, "profile_field": None, "confidence": 0.0})

        # Phase 2: AI mapping for remaining fields
        if unmapped_fields:
            try:
                ai_mappings = await self._ai_map(unmapped_fields)
                # Merge AI results
                for ai_map in ai_mappings:
                    for r in results:
                        if r["field_name"] == ai_map.get("field_name") and r["profile_field"] is None:
                            r["profile_field"] = ai_map.get("profile_field")
                            r["confidence"] = ai_map.get("confidence", 0.7)
                            r["language_detected"] = ai_map.get("language_detected", "unknown")
                            r["semantic_meaning"] = ai_map.get("semantic_meaning", "")
                            break
            except Exception as e:
                logger.warning(f"AI mapping failed (using instant only): {e}")

        return results

    def _try_partial_match(self, normalized: str) -> Optional[str]:
        """Try partial keyword matching."""
        for keyword, profile_field in INSTANT_MAPPINGS.items():
            if keyword in normalized or normalized in keyword:
                return profile_field
        return None

    async def _ai_map(self, fields: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Use AI for complex/ambiguous field mapping."""
        fields_text = "\n".join(
            f"- {f.get('field_name') or f.get('field_label') or f.get('label', '')}"
            for f in fields
        )

        messages = [
            {"role": "system", "content": FIELD_MAPPING_PROMPT},
            {"role": "user", "content": f"Map these fields:\n{fields_text}"},
        ]

        result = await ai_provider.chat_completion_json(messages=messages)
        return result.get("mappings", [])


# Singleton
field_mapper = FieldMapper()
