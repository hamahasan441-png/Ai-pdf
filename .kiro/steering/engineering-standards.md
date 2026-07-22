# AI-PDF Engineering Standards

## Dart Type Safety (CRITICAL)

These rules prevent the most common CI failures in this project:

### 1. Never use `math.max`, `math.min`, or `.clamp()` in an `int` context

The Dart compiler resolves `math.max<T extends num>(int, int)` as returning `num`, not `int`.
Similarly, `num.clamp(int, int)` returns `num`. This causes compile errors in release builds
where the result is used as a list index, int parameter, or int return value.

**Instead**, use plain integer arithmetic:
```dart
// BAD: returns num, fails in release
final half = math.max(1, window ~/ 2);
final y0 = (y - half).clamp(0, height - 1);

// GOOD: always int
int half = window ~/ 2;
if (half < 1) half = 1;

var y0 = y - half;
if (y0 < 0) y0 = 0;
```

**Exception:** `double.clamp(double, double)` returns `double` — safe to use freely.

### 2. Always use explicit imports

Never rely on transitive exports. The release/AOT compiler is stricter than debug mode.
```dart
// BAD: Float64List works in debug (transitively exported by Flutter) but fails in release
// GOOD:
import 'dart:typed_data' show Float64List;
```

### 3. Extension getters require explicit import at every use site

If you define `extension Foo on MyEnum { String get label {...} }`, every file that
calls `.label` must import the file containing the extension — even if the enum itself
is already visible via another import.

## Test Assertions

### 4. Verify every numeric assertion mathematically before writing it

Common trap: `130 > 128` is TRUE (not false). Before writing `expect(result, [0,0,0,...])`,
compute the expected output mentally or with a Python one-liner.

### 5. For Otsu/threshold algorithms, use `greaterThanOrEqualTo` at exact boundaries

When two histogram modes are delta functions, Otsu returns the first maximiser (the lower mode),
not a value between the modes. Use `>=` not `>`.

## Architecture

### 6. Heavy pixel loops run in isolates

Any O(width×height) computation (warp, binarization, filter) must be wrapped in `compute()`
with a top-level or static function. Never do pixel loops on the UI thread.

### 7. The `image` package's v4 API

- `img.decodeImage(bytes)` returns `Image?` (nullable)
- `img.getPixel(x, y)` returns a `Pixel` with `.r`, `.g`, `.b` as `num`
- Always `.toInt()` when extracting channels for integer arithmetic
- `img.copyResize`, `img.copyRotate`, `img.encodeJpg` are the correct v4 names

### 8. The `pdf` package's MemoryImage

- `pw.MemoryImage(bytes)` has nullable `.width`/`.height` (decoded lazily)
- Never use `image.width!` — use `PdfPageFormat.a4` with `BoxFit.contain` (same pattern as
  `offline_pdf_service.dart`, `editor_export_service.dart`)

## Code Style

### 9. `const` constructors for stateless services

Every pure service class should have a `const` constructor and be instantiated as
`static const _svc = MyService()` or `const MyService()`.

### 10. No `import 'dart:math'` in the import for `int` arithmetic

If you only need `max(a, b)` for integers, write `a > b ? a : b` inline.
Only import `dart:math` when you need `sqrt`, `atan2`, `pi`, etc.
