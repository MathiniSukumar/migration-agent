# Framework Checks

Load this reference only when imports, annotations, or tests indicate framework behavior.

## Spring

- Prefer constructor injection with `val` properties.
- Keep proxy constraints in mind: Spring classes/methods may need to remain `open` depending on plugins and project configuration.
- Put validation and request binding annotations on the target Spring reads, often constructor parameters or fields.
- Preserve `@Transactional`, `@Async`, `@Scheduled`, cache annotations, and visibility. Private methods are not proxied.

## Jackson

- Constructor-based DTOs usually need annotations on parameters or fields, depending on existing mapper configuration.
- Preserve property names with `@JsonProperty` when Java getter names, acronyms, booleans, or custom names are involved.
- Use default values carefully; they can change deserialization behavior.
- Do not convert to `data class` when no-arg construction, mutable fields, or identity behavior is required by configuration.

## JPA And Hibernate

- Do not make JPA entities `data class` by default.
- Keep entities `open` if the project lacks all-open/no-arg compiler plugins or runtime proxying requires it.
- Preserve no-arg constructor requirements.
- Prefer mutable `var` properties for persistent fields when Hibernate writes them.
- Put mapping annotations on fields or getters to match the access strategy already used by the Java entity.
- Avoid changing equality for managed entities.

## Lombok

- Expand Lombok behavior before converting: constructors, getters/setters, builders, equals/hashCode, toString, null checks, and default values.
- For `@Builder`, preserve Java builder API if callers use it. Kotlin default parameters are not a drop-in replacement for Java builder call sites.
- For `@Value`, confirm whether the class is a DTO candidate or whether Java callers depend on exact generated methods.

## Dependency Injection

- For `javax.inject` or `jakarta.inject`, inspect whether Spring, Dagger/Hilt, or Guice owns the lifecycle.
- Preserve constructor annotations when injection frameworks require them.
- Keep qualifier annotations on the exact parameter or field target.

## Tests

- JUnit lifecycle methods can become Kotlin functions, but visibility and annotations must remain discoverable.
- Mockito matchers and Kotlin nullability often conflict; use Kotlin-friendly matchers if already present in the project.
- Backtick test names are fine for Kotlin tests, but avoid renaming when reports or filters depend on method names.
