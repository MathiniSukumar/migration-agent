---
name: java-to-kotlin-migration
description: Convert Java source files to Kotlin while preserving behavior, public APIs, build compatibility, tests, annotations, nullability contracts, and interop. Use when asked to migrate, port, translate, or convert .java files, Java packages, Java tests, Java DTOs, Java services, or mixed Java/Kotlin JVM code to Kotlin.
---

# Java To Kotlin Migration

## Scope

Use this skill only for Java-to-Kotlin migration work. Do not broaden into general Kotlin feature design, backend rewrites, framework modernization, architecture cleanup, or style-only refactors unless they are required to keep the converted code compiling and behaviorally equivalent.

Prefer incremental migration: convert one file or one small dependency-ordered batch, verify it, then continue.

## Workflow

1. Identify the target Java files and their module.
2. Scan imports, annotations, inheritance, public members, tests, and callers.
3. Read only the needed references:
   - `references/conversion-rules.md` for every migration.
   - `references/framework-checks.md` when imports or annotations suggest Spring, Jackson, JPA/Hibernate, Lombok, dependency injection, JUnit, Mockito, or similar framework behavior.
   - `references/testing.md` before verification or when build commands are unclear.
4. Convert faithfully first, then make Kotlin idiomatic in small steps.
5. Preserve binary/source API where Java callers still exist.
6. Replace the `.java` file with a `.kt` file only after the converted code has been reviewed for the invariants below.
7. Run the narrowest useful compile/test command, then broaden if the change affects shared contracts.

## Guard Rails

Follow these rules during every migration:

- Work on one file at a time unless the user explicitly asks for a batch migration.
- Do not perform unrelated cleanup, naming changes, architecture changes, dependency upgrades, or framework modernization while converting Java to Kotlin.
- Do not change package names, module boundaries, source-set layout, routes, persistence mappings, serialization field names, database behavior, or public contracts unless required for compilation and reported clearly.
- Do not edit generated code, vendored code, build output, or third-party copied sources unless the user specifically targets those files.
- Do not add Kotlin build configuration unless the project lacks Kotlin support and the migration cannot compile without it; keep build changes minimal and explain them.
- Do not delete the original `.java` file until the `.kt` replacement has been reviewed and the narrowest available compile/test command has passed. If no verification command is available, keep the change small and report the gap.
- Do not convert classes to `data class`, `object`, top-level functions, extension functions, coroutines, sealed hierarchies, or Kotlin-only APIs unless behavior and Java interoperability remain equivalent.
- Do not use `!!` to force nullability. Keep uncertain values nullable or handle null explicitly.
- Do not assume annotation targets. Preserve or add use-site targets such as `@field:`, `@get:`, `@set:`, `@param:`, or `@property:` when frameworks depend on reflection.
- Do not hide migration uncertainty. Leave a concise note in the completion report for any unverified behavior, risky nullability choice, framework mapping, or API compatibility concern.

## Required Invariants

Check these after each meaningful edit:

- Behavior stays equivalent, including side effects, evaluation order, exceptions, synchronization, equality, and default values.
- Public API remains compatible unless the user explicitly approved a breaking change.
- Nullability is intentional; platform types are not guessed into unsafe non-null types.
- Framework annotations still bind to the correct target: field, getter, setter, parameter, receiver, or class.
- Java interoperability is preserved with `@JvmStatic`, `@JvmField`, `@JvmOverloads`, `@Throws`, explicit visibility, or companion/object choices when needed.

## Conversion Order

For a batch, sort files from leaves upward:

1. Constants, simple value objects, utility classes with no project-local imports.
2. DTOs, request/response models, exceptions.
3. Domain services and adapters.
4. Controllers, scheduled jobs, dependency-injected entry points.
5. Tests last or immediately after the class they cover.

When dependency order is ambiguous, convert one file and update references before moving on.

## Completion Report

Finish with:

- Files converted.
- Commands run and results.
- Any unverified behavior or test gaps.
- Any deliberate API or interop decisions, especially nullability and annotation site targets.
