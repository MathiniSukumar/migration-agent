# Conversion Rules

## First Pass: Faithful Kotlin

Start with a conservative 1:1 translation:

- Keep package names, class names, method names, overloads, visibility, and annotations.
- Preserve explicit constructors when Java callers may depend on overload shape.
- Convert static members to `companion object`, top-level declarations, or `object` based on Java call-site needs.
- Keep checked exception behavior visible to Java callers with `@Throws` when callers catch or declare the exception.
- Preserve synchronization semantics with `@Synchronized`, `synchronized(lock)`, volatile fields, or Java concurrency types.

Do not introduce coroutines, sealed hierarchies, extension-heavy APIs, or large expression rewrites during this pass.

## Nullability And Mutability

Audit every type:

- Use nullable types for values that can be absent, Java APIs that return null, optional fields, lazy initialization, and framework-injected properties that may be unset during construction.
- Use non-null types only when constructors, validation, annotations, or usage prove non-null.
- Prefer `val` for final fields and stable locals; use `var` for reassignment, mutable framework fields, counters, and stateful objects.
- For late framework initialization, prefer constructor injection. Use `lateinit var` only when the framework requires property injection and the property is definitely assigned before use.

Do not silence uncertainty with `!!`; handle null explicitly or leave the type nullable.

## Collections And Arrays

Choose collection types by contract:

- Java read-only API surface: `List<T>`, `Set<T>`, `Map<K, V>`.
- Mutating API surface or internal mutation: `MutableList<T>`, `MutableSet<T>`, `MutableMap<K, V>`.
- Java arrays that callers depend on: `Array<T>`, primitive arrays, or varargs as appropriate.
- Preserve defensive copies when Java code copied collections to avoid aliasing.

Be careful with Kotlin read-only interfaces: they are not immutable guarantees when backed by mutable Java collections.

## Idiomatic Pass

After the faithful pass compiles mentally, apply limited idioms:

- Bean getters/setters can become Kotlin properties if Java interoperability remains acceptable.
- Simple POJOs can become `data class` only when identity, no-arg construction, inheritance, and framework behavior allow it.
- Convert trivial null checks to safe calls or Elvis expressions when readability improves.
- Convert anonymous listeners/lambdas only when overload resolution stays unambiguous.
- Convert string concatenation to templates only when evaluation and formatting stay the same.

Avoid clever scope functions if they obscure side effects or lifecycle order.

## Java Interop Decisions

Add interop annotations when Java callers or frameworks need the Java shape:

- `@JvmStatic` for static-style calls from Java.
- `@JvmField` for constants/fields that must not become accessor methods.
- `const val` only for compile-time primitive/String constants.
- `@JvmOverloads` only when Java callers need default-argument overloads.
- `@file:JvmName` only when replacing Java utility classes with top-level functions and Java call sites must keep the old class name.

Check generated names for companion objects and top-level functions before assuming Java call sites still compile.

## Known Risk Areas

- Kotlin keywords used as Java identifiers require backticks.
- Wildcard generics may need `out`, `in`, or `@JvmSuppressWildcards`.
- SAM conversion can select a different overload.
- `equals`, `hashCode`, and `toString` can change when introducing `data class`.
- `BigDecimal`, date/time, and floating point comparisons must stay exactly equivalent.
- `Optional<T>` should not always become nullable `T?`; preserve public Java APIs when callers expect `Optional`.
- Package-private Java visibility has no exact Kotlin equivalent. Prefer `internal` only when module boundaries match the old intent.
