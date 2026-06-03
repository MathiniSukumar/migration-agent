# Testing And Verification

Use the narrowest reliable command first, then broaden when shared code changed.

## Discover The Build

Look for build files in the module:

- Gradle: `settings.gradle`, `settings.gradle.kts`, `build.gradle`, `build.gradle.kts`, `gradlew`, `gradlew.bat`.
- Maven: `pom.xml`, `mvnw`, `mvnw.cmd`.
- Android: `com.android.application`, `com.android.library`, `android {}` blocks.

If the project has no JVM build, validate by inspection and report that no compile command was available.

## Gradle Commands

On Windows, prefer the wrapper when present:

```powershell
.\gradlew.bat compileKotlin
.\gradlew.bat test
.\gradlew.bat :module:compileKotlin
.\gradlew.bat :module:test --tests "com.example.FooTest"
```

If only system Gradle is available:

```powershell
gradle compileKotlin
gradle test
```

## Maven Commands

Prefer the wrapper when present:

```powershell
.\mvnw.cmd -q test
.\mvnw.cmd -q -DskipTests package
.\mvnw.cmd -q -Dtest=FooTest test
```

If only system Maven is available:

```powershell
mvn -q test
mvn -q -DskipTests package
```

## Verification Checklist

- The converted `.kt` file compiles.
- Existing tests for the converted type pass.
- Mixed Java/Kotlin callers still compile.
- Framework annotations bind to the same runtime element.
- Serialization/deserialization names and constructor behavior are preserved.
- Public constants, static methods, overloads, exceptions, and visibility remain compatible.
- No `!!` was added without a clear reason.
- No large unrelated refactor was included with the migration.
